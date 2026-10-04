#!/usr/bin/env bash
# Combine multiple video files (.mp4, .webm, .ts, .mkv, .m4v, and/or .avi, mixed
# freely) with matching .srt/.vtt/.dfxp subtitle files or embedded subtitle
# tracks, of varying resolution, into a single .mkv, scaling everything up
# to the largest resolution found and shifting subtitle timestamps to match.
#
# Usage: ./combine_mp4_srt.sh [-n] /path/to/directory output.mkv
#   -n  dry run: list the files in processing order and exit (output.mkv
#       may be omitted)
#
# Requirements: ffmpeg, ffprobe, python3 (all on PATH)
# Subtitle matching accepts: name.srt, name.vtt, name.dfxp, name_en.srt,
# name.eng.vtt, name-EN.srt, name English.srt, name en_US.srt, etc. (any
# separator including a space, any language code or full language name, an
# optional region suffix like _US, any case). DFXP/TTML cues are only
# recognized with clock-time timestamps (HH:MM:SS.mmm); frame- or
# tick-based timestamps are skipped with a warning. If more than one
# sidecar format exists for the same file, priority is srt > vtt > dfxp.
# If no matching external sidecar file is found, an embedded text-based
# subtitle track (subrip/ass/ssa/mov_text/webvtt), if any, is extracted
# and used instead — preferring one tagged language eng/en, else the
# lowest stream index. Bitmap-based embedded tracks (PGS/VobSub/DVB)
# can't be converted to text and are skipped with a warning.
# Files with no usable subtitle at all, or directories with no subtitles
# anywhere, are handled gracefully — output just has silent/no subtitles
# for those.

set -euo pipefail

USAGE="Usage: $0 [-n] <directory> <output.mkv>
  -n  dry run: list the files in the order they would be processed, then exit"

DRY_RUN=0
while getopts ":n" opt; do
  case "$opt" in
    n) DRY_RUN=1 ;;
    *) echo "$USAGE" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

DIR="${1:?$USAGE}"
if [ "$DRY_RUN" -eq 1 ]; then
  OUT="${2:-}"
else
  OUT="${2:?$USAGE}"
  renice -n 20 $$
fi

cd "$DIR"

# 1. Sorted (natural/numeric) list of video files (.mp4, .webm, .ts, .avi).
# Uses python3 for the sort (not `ls -v` / `sort -V`) so this works
# identically on Linux and stock macOS: macOS's BSD `ls` has no -v flag,
# and macOS ships bash 3.2 by default, which lacks the `mapfile` builtin —
# so we populate the array with a plain while/read loop instead.
MP4S=()
while IFS= read -r line; do
  MP4S+=("$line")
done < <(python3 - <<'PYEOF'
import glob, re

def natural_key(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r'(\d+)', s)]

ext_re = re.compile(r'\.(mp4|webm|ts|avi|mkv|m4v)$', re.IGNORECASE)
files = [f for f in glob.glob('*') if ext_re.search(f)]
for f in sorted(files, key=natural_key):
    print(f)
PYEOF
)

if [ ${#MP4S[@]} -eq 0 ]; then
  echo "No mp4 files found in $DIR" >&2
  exit 1
fi

echo "Found ${#MP4S[@]} mp4 files (in order):"
printf '  %s\n' "${MP4S[@]}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run — nothing processed."
  exit 0
fi

# 2. Validate every file is actually readable before doing any real work
#    (resolution probing, subtitle extraction, GPU encoding). A single
#    truncated/corrupt file (e.g. an interrupted download, showing up as
#    ffprobe's "moov atom not found") would otherwise abort the whole run
#    partway through under `set -e` — potentially after expensive encoding
#    has already completed for earlier files. Collecting every bad file up
#    front means one fix-and-rerun cycle instead of whack-a-mole (fix file
#    1, rerun, hit file 2, rerun, ...).
BAD_FILES=()
for f in "${MP4S[@]}"; do
  if ! err=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>&1 >/dev/null); then
    BAD_FILES+=("$f: ${err:-unknown error}")
  fi
done
if [ ${#BAD_FILES[@]} -gt 0 ]; then
  echo "ERROR: ${#BAD_FILES[@]} file(s) could not be read (corrupt or truncated?):" >&2
  printf '  %s\n' "${BAD_FILES[@]}" >&2
  exit 1
fi

# 3. Determine target (max) resolution across all files
MAXW=0
MAXH=0
for f in "${MP4S[@]}"; do
  # Pulled as two separate calls. Some ffprobe builds (seen on macOS) emit
  # a stray trailing empty CSV field when width/height are requested
  # together with a custom separator; MPEG-TS files additionally report
  # every stream twice (once grouped under [PROGRAM], once again as a flat
  # [STREAM] listing) since TS carries PMT/program info that mp4/webm
  # containers don't. We capture the full output first, then take only the
  # first line via bash parameter expansion (piping ffprobe directly into
  # `head -n1` under `set -o pipefail` would cause a SIGPIPE/exit-141 abort
  # when head closes the pipe early) before filtering to digits-only.
  raw_w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$f")
  raw_h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$f")
  w=$(printf '%s' "${raw_w%%$'\n'*}" | tr -dc '0-9')
  h=$(printf '%s' "${raw_h%%$'\n'*}" | tr -dc '0-9')
  if [ -z "$w" ] || [ -z "$h" ]; then
    echo "ERROR: could not read resolution for '$f' (got width='$w' height='$h')" >&2
    exit 1
  fi
  echo "  $f: ${w}x${h}"
  [ "$w" -gt "$MAXW" ] && MAXW=$w
  [ "$h" -gt "$MAXH" ] && MAXH=$h
done
# force even dimensions (required by most codecs)
MAXW=$(( MAXW % 2 == 0 ? MAXW : MAXW + 1 ))
MAXH=$(( MAXH % 2 == 0 ? MAXH : MAXH + 1 ))
echo "Target resolution: ${MAXW}x${MAXH}"

# The GPU-accelerated encoder (VideoToolbox, below) does bitrate-based rate
# control rather than libx264's constant-quality -crf, so scale a target
# bitrate to the chosen resolution instead: ~8 Mbps at 1920x1080, scaled
# proportionally by pixel count, with a floor so small sources don't get
# starved.
REF_BITRATE=8000000
REF_PIXELS=$(( 1920 * 1080 ))
BITRATE=$(( REF_BITRATE * MAXW * MAXH / REF_PIXELS ))
[ "$BITRATE" -lt 1500000 ] && BITRATE=1500000
echo "Target video bitrate: $((BITRATE / 1000000))M"

# 4. Build one continuous SRT FIRST (fast) — shifting each file's timestamps
#    by the cumulative duration of the files before it. Doing this before the
#    slow video encode means a subtitle naming problem fails in seconds
#    instead of after a long re-encode.
python3 - "${MP4S[@]}" <<'PYEOF' > combined.srt
import sys, subprocess, re, os, json
import xml.etree.ElementTree as ET

def get_duration(path):
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", path
    ]).decode().strip()
    return float(out)

def ts_to_ms(ts):
    # Handles both SRT (HH:MM:SS,mmm) and VTT (HH:MM:SS.mmm or MM:SS.mmm —
    # VTT allows omitting the hours component) timestamp formats.
    m = re.match(r'(?:(\d+):)?(\d+):(\d+)[.,](\d+)', ts.strip())
    if not m:
        raise ValueError(f"unrecognized timestamp: {ts!r}")
    h = int(m.group(1)) if m.group(1) else 0
    mi, s, frac = int(m.group(2)), int(m.group(3)), m.group(4)
    ms = int((frac + "000")[:3])  # normalize to 3-digit milliseconds
    return ((h * 60 + mi) * 60 + s) * 1000 + ms

def ms_to_ts(ms):
    ms = max(0, int(ms))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

SUBTITLE_EXT_PRIORITY = {"srt": 0, "vtt": 1, "dfxp": 2}

def find_subtitle(mp4):
    # Matches name.srt / name.vtt / name.dfxp, with an optional language
    # suffix after any separator (space, ., _, or -): name_en.srt,
    # name.eng.vtt, name-EN.srt, "name English.srt", "name en_US.srt",
    # any case. The suffix can be a short code or a full language name,
    # optionally followed by a region code (e.g. en_US). If more than one
    # candidate exists for the same file, priority is srt > vtt > dfxp
    # (arbitrary but deterministic — simplest formats first). Strips
    # .mp4, .webm, .ts, .avi, .mkv, or .m4v as the base.
    base = re.sub(r'\.(mp4|webm|ts|avi|mkv|m4v)$', '', mp4, flags=re.IGNORECASE)
    pattern = re.compile(
        r'^' + re.escape(base) + r'([ ._-][A-Za-z]+([_-][A-Za-z]{2,3})?)?\.(srt|vtt|dfxp)$',
        re.IGNORECASE,
    )
    matches = [f for f in os.listdir('.') if pattern.match(f)]
    if not matches:
        return None
    matches.sort(key=lambda f: (SUBTITLE_EXT_PRIORITY[f.lower().rsplit('.', 1)[-1]], f))
    return matches[0]

mp4_files = sys.argv[1:]
offset_ms = 0
counter = 1
out_lines = []
matched = 0
skipped = []

def read_subtitle_text(path):
    # Not all subtitle files are valid UTF-8 — older tools (especially on
    # Windows) commonly export cp1252 or plain Latin-1. Try utf-8-sig first
    # (handles both BOM and plain UTF-8), then fall back through common
    # legacy encodings. latin-1 maps every byte 0-255 to a codepoint, so it
    # never raises and is used as a guaranteed-success last resort.
    for enc in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            with open(path, encoding=enc) as f:
                text = f.read()
            if enc != "utf-8-sig":
                print(f"  note: {path} is not valid UTF-8, read as {enc}",
                      file=sys.stderr)
            return text
        except UnicodeDecodeError:
            continue
    # Unreachable in practice since latin-1 never raises, but keep a safe
    # fallback just in case.
    with open(path, encoding="latin-1", errors="replace") as f:
        return f.read()

TEXT_SUBTITLE_CODECS = {"subrip", "ass", "ssa", "mov_text", "webvtt", "text"}
BITMAP_SUBTITLE_CODECS = {"hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle"}

def extract_embedded_subtitle(video_path, tmp_name):
    # Fallback when no external sidecar matches: probe for an embedded
    # text-based subtitle stream and extract it to tmp_name (.srt). Must
    # never raise — this runs inside the combined.srt-generating block
    # under `set -e`; any failure here should just mean "no subtitle".
    try:
        probe = subprocess.check_output([
            "ffprobe", "-v", "error", "-select_streams", "s",
            "-show_entries", "stream=index,codec_name:stream_tags=language",
            "-of", "json", video_path,
        ])
        streams = json.loads(probe).get("streams", [])
    except Exception as e:
        print(f"  note: subtitle probe failed for {video_path}: {e}", file=sys.stderr)
        return None

    candidates = []
    for s in streams:
        codec = (s.get("codec_name") or "").lower()
        if codec in BITMAP_SUBTITLE_CODECS:
            print(f"  note: {video_path} stream #{s.get('index')} is a "
                  f"bitmap subtitle ({codec}) — can't convert to SRT, skipping",
                  file=sys.stderr)
            continue
        if codec not in TEXT_SUBTITLE_CODECS:
            continue
        lang = (s.get("tags") or {}).get("language", "").lower()
        candidates.append((s["index"], lang))

    if not candidates:
        return None

    # Prefer an English-tagged track; otherwise lowest stream index.
    stream_index, _ = min(
        candidates, key=lambda c: (0 if c[1] in ("eng", "en") else 1, c[0])
    )

    try:
        subprocess.run(
            ["ffmpeg", "-y", "-v", "error", "-i", video_path,
             "-map", f"0:{stream_index}", "-c:s", "srt", tmp_name],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as e:
        print(f"  note: failed to extract embedded subtitle stream "
              f"#{stream_index} from {video_path}: "
              f"{e.stderr.decode(errors='replace').strip()}", file=sys.stderr)
        return None

    if not os.path.exists(tmp_name) or os.path.getsize(tmp_name) == 0:
        return None
    return tmp_name

def parse_srt_vtt(content):
    # Returns a list of (start_ts, end_ts, text) cues.
    cues = []
    blocks = re.split(r'\n\s*\n', content.strip()) if content.strip() else []
    for block in blocks:
        lines = block.splitlines()
        time_line_idx = next(
            (idx for idx, l in enumerate(lines) if '-->' in l), None
        )
        if time_line_idx is None:
            # Skips non-cue blocks transparently: VTT "WEBVTT" header,
            # NOTE/STYLE/REGION blocks, blank metadata, etc.
            continue
        start_raw, end_raw = lines[time_line_idx].split('-->')
        start = start_raw.strip()
        # VTT allows cue settings after the end timestamp on the same line
        # (e.g. "00:00:04.000 align:start position:10%") — take just the
        # timestamp token.
        end = end_raw.strip().split()[0]
        text = "\n".join(lines[time_line_idx + 1:])
        cues.append((start, end, text))
    return cues

def parse_dfxp(content):
    # DFXP/TTML is XML rather than line-based, e.g.:
    #   <p begin="00:00:01.040" end="00:00:04.160">Hello</p>
    # Strip namespace declarations so plain tag/attribute lookups work
    # without namespace-aware queries — covers the common case (e.g.
    # YouTube's DFXP export) rather than full TTML support. Only
    # clock-time timestamps (HH:MM:SS.mmm, matching ts_to_ms) are
    # supported; frame-based or tick-based timestamps aren't recognized
    # and those cues are skipped with a warning rather than guessed at.
    stripped = re.sub(r'\sxmlns(:\w+)?="[^"]*"', '', content)
    try:
        root = ET.fromstring(stripped)
    except ET.ParseError as e:
        print(f"  WARNING: could not parse DFXP/TTML subtitle: {e}", file=sys.stderr)
        return []
    cues = []
    for p in root.iter():
        if p.tag.rsplit('}', 1)[-1] != 'p':
            continue
        begin, end = p.get('begin'), p.get('end')
        if not begin or not end:
            continue
        if not re.match(r'^(?:\d+:)?\d+:\d+[.,]\d+$', begin.strip()):
            print(f"  WARNING: skipping DFXP cue with unsupported timestamp "
                  f"format: begin={begin!r}", file=sys.stderr)
            continue
        text = ' '.join(''.join(p.itertext()).split())
        cues.append((begin, end, text))
    return cues

for i, mp4 in enumerate(mp4_files):
    sub = find_subtitle(mp4)
    if sub:
        print(f"  matched: {mp4} -> {sub}", file=sys.stderr)
        matched += 1
        content = read_subtitle_text(sub)
    else:
        embedded = extract_embedded_subtitle(mp4, f"embedded_{i}.srt")
        if embedded:
            print(f"  matched: {mp4} -> {embedded} (embedded subtitle track)",
                  file=sys.stderr)
            matched += 1
            sub = embedded
            content = read_subtitle_text(embedded)
        else:
            print(f"  WARNING: no subtitle found for {mp4}", file=sys.stderr)
            skipped.append(mp4)
            content = ""

    if sub and sub.lower().endswith('.dfxp'):
        cues = parse_dfxp(content)
    else:
        cues = parse_srt_vtt(content)

    for start, end, text in cues:
        new_start = ms_to_ts(ts_to_ms(start) + offset_ms)
        new_end = ms_to_ts(ts_to_ms(end) + offset_ms)
        out_lines += [str(counter), f"{new_start} --> {new_end}", text, ""]
        counter += 1

    offset_ms += get_duration(mp4) * 1000

print(f"Matched {matched}/{len(mp4_files)} subtitle files.", file=sys.stderr)
if skipped:
    print(f"No subtitles for: {', '.join(skipped)}", file=sys.stderr)

if not out_lines:
    # No subtitle files anywhere in the directory — that's a valid case
    # (just an mp4-only batch), not an error. Leave combined.srt empty; the
    # bash script below detects this and skips the subtitle mux step.
    print("No subtitle files found for any mp4 — proceeding without subtitles.",
          file=sys.stderr)
else:
    print("\n".join(out_lines))
PYEOF

echo "Combined subtitle track written to combined.srt"

# 5. Normalize each file to the target resolution/fps/audio format ONE AT A
#    TIME, then join the normalized parts with the concat demuxer (stream
#    copy, no decoding). This is deliberately NOT one giant filter_complex
#    across all inputs: ffmpeg opens a decoder for every -i input up front,
#    and each decoder can spin up its own thread pool — with enough input
#    files that can exhaust the OS's per-user thread/process limit (seen in
#    practice as "Error while opening decoder: Resource temporarily
#    unavailable" on macOS well before dozens of files). Encoding
#    sequentially means only one decoder is ever open at a time.
VF="scale=${MAXW}:${MAXH}:force_original_aspect_ratio=decrease,pad=${MAXW}:${MAXH}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=30"
AF="aformat=sample_rates=48000:channel_layouts=stereo,aresample=async=1:first_pts=0"

PARTS=()
: > concat_list.txt
for i in "${!MP4S[@]}"; do
  part="part_${i}.ts"
  echo "Encoding part $((i+1))/${#MP4S[@]}: ${MP4S[$i]}..."
  # -hwaccel videotoolbox decodes on the GPU/media engine instead of the
  # CPU; -hwaccel_output_format nv12 brings frames back into system memory
  # in a format the software scale/pad filter chain above already expects,
  # so no filter changes are needed. h264_videotoolbox is the matching
  # hardware encoder — it's bitrate-based (no -crf), hence $BITRATE above.
  ffmpeg -y -hwaccel videotoolbox -hwaccel_output_format nv12 \
    -i "${MP4S[$i]}" -vf "$VF" -af "$AF" \
    -c:v h264_videotoolbox -b:v "$BITRATE" -c:a aac -b:a 192k \
    -avoid_negative_ts make_zero \
    -sn \
    -f mpegts "$part"
  PARTS+=("$part")
  printf "file '%s'\n" "$part" >> concat_list.txt
done

echo "Joining ${#PARTS[@]} normalized parts (fast stream copy, no re-decode)..."
ffmpeg -y -f concat -safe 0 -i concat_list.txt -c copy combined_video.mkv

# 6. Mux subtitles into the final mkv — but only if we actually built any.
#    An empty/whitespace-only combined.srt means no srt files existed for
#    this batch at all, which is fine: just deliver the video as-is.
#    The subtitle codec has to suit the output container: MP4/MOV can't
#    carry SubRip and need mov_text instead, while MKV takes srt as-is.
case "$(printf '%s' "${OUT##*.}" | tr '[:upper:]' '[:lower:]')" in
  mp4|m4v|mov) SUB_CODEC=mov_text ;;
  *) SUB_CODEC=srt ;;
esac
if [ -s combined.srt ] && [ -n "$(tr -d '[:space:]' < combined.srt)" ]; then
  ffmpeg -y -i combined_video.mkv -i combined.srt \
    -map 0:v -map 0:a -map 1:s \
    -c:v copy -c:a copy -c:s "$SUB_CODEC" \
    "$OUT"
else
  echo "No subtitles to mux — remuxing video-only result."
  ffmpeg -y -i combined_video.mkv -map 0:v -map 0:a -c copy "$OUT"
fi

echo "Done: $OUT"
