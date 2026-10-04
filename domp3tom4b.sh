#!/bin/bash
#
# domp3tom4b.sh - Combine a folder of numbered MP3/M4A/M4B files into ONE chaptered M4B.
#
#   * Every .mp3/.m4a/.m4b in the folder is joined, in sorted order, into a single .m4b.
#   * The number in each file name becomes a chapter marker ("Chapter N").
#   * Audio is re-encoded to 64 kbps mono AAC (from 128 kbps stereo source).
#   * A cover.jpg / folder.jpg in the folder (if present) is embedded.
#
# Usage:
#   ./domp3tom4b.sh [-a AUTHOR] [-t TITLE] [-y YEAR] [-n] [SOURCE_DIR] [OUTPUT.m4b]
#
#   -a AUTHOR     author / narrator name        (optional)
#   -t TITLE      book title                    (optional; else guessed from names)
#   -y YEAR       year published               (optional)
#   -n            dry run: show file -> chapter ordering and exit, no encode
#   SOURCE_DIR    folder with the source files  (default: current directory)
#   OUTPUT.m4b    output file name              (default: "<TITLE>.m4b")
#
# Requires: ffmpeg + ffprobe (MacPorts: /opt/local/bin).

set -euo pipefail

AUTHOR=""
TITLE=""
YEAR=""
DRY_RUN=0

while getopts ":a:t:y:nh" opt; do
	case "$opt" in
		a) AUTHOR="$OPTARG" ;;
		t) TITLE="$OPTARG" ;;
		y) YEAR="$OPTARG" ;;
		n) DRY_RUN=1 ;;
		h) sed -n '2,21p' "$0"; exit 0 ;;
		:) echo "Option -$OPTARG needs an argument" >&2; exit 2 ;;
		\?) echo "Unknown option -$OPTARG" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

SRC_DIR="${1:-.}"
cd "$SRC_DIR"

# ---- collect and sort the source files (mp3/m4a/m4b) -------------------------
shopt -s nullglob nocaseglob
mp3s=( *.mp3 *.m4a *.m4b )
shopt -u nullglob nocaseglob
if (( ${#mp3s[@]} == 0 )); then
	echo "No .mp3/.m4a/.m4b files found in: $PWD" >&2
	exit 1
fi
# Sort by:
#   1. kind      - front matter (Prologue/Preface/Foreword/Introduction) sorts
#                  before numbered chapters; back matter (Epilogue/Afterword/
#                  Appendix/Acknowledgments) sorts after them
#   2. disc      - "Disc N"/"CD N" anywhere in the name, but only as a whole
#                  word (so it doesn't fire on a substring of something else,
#                  e.g. an ASIN/code that happens to contain "cd")
#   3. chapter   - the number after the word "Chapter"; full-width digits
#                  ("４") are normalized to ASCII first, and only the segment
#                  after the last " - " is searched so an incidental
#                  "Chapter" earlier in a book's own title isn't picked up
#   4. sub-part  - "Part N" within a chapter, or (if there's no "Part") a
#                  bare letter directly on the chapter number, e.g.
#                  "Chapter 4a"/"4b", used as a fallback order (a=1, b=2, ...)
#   5. full name - natural/case-folded tiebreak
normalize_digits() {
	local s="$1" fw='０１２３４５６７８９' i
	for (( i = 0; i < 10; i++ )); do
		s="${s//${fw:i:1}/$i}"
	done
	printf '%s' "$s"
}

IFS=$'\n' mp3s=( $(
	for f in "${mp3s[@]}"; do
		stem="$(normalize_digits "${f%.*}")"

		kind=1
		if printf '%s' "$stem" | grep -qiE '(^|[^A-Za-z])(prologue|preface|foreword|introduction)([^A-Za-z]|$)'; then
			kind=0
		elif printf '%s' "$stem" | grep -qiE '(^|[^A-Za-z])(epilogue|afterword|appendix|acknowledge?ments?)([^A-Za-z]|$)'; then
			kind=2
		fi

		disc="$(printf '%s' "$stem" | sed -nE \
			's/.*(^|[^A-Za-z0-9])[Dd][Ii][Ss][Cc][ _-]*([0-9]+)([^A-Za-z0-9]|$).*/\2/p; t
			 s/.*(^|[^A-Za-z0-9])[Cc][Dd][ _-]*([0-9]+)([^A-Za-z0-9]|$).*/\2/p')"
		stripped="$(printf '%s' "$stem" | sed -E \
			's/[ _-]*[Dd][Ii][Ss][Cc][ _-]*[0-9]+[ _-]*//; s/[ _-]*[Cc][Dd][ _-]*[0-9]+[ _-]*//')"

		# only look for the chapter marker in the segment after the last
		# " - ", so a title like "Dune: Chapter House - Chapter 3" doesn't
		# match the "Chapter" in the book's own title
		suffix="$(printf '%s' "$stripped" | sed -E 's/.*[[:space:]]-[[:space:]]//')"
		[[ -n "$suffix" ]] || suffix="$stripped"

		track="$(printf '%s' "$suffix" | sed -nE 's/.*[Cc]hapter[ _-]*([0-9]+).*/\1/p')"
		if [[ -n "$track" ]]; then
			part="$(printf '%s' "$suffix" | sed -nE 's/.*[Pp]art[ _-]*([0-9]+).*/\1/p')"
			if [[ -z "$part" ]]; then
				letter="$(printf '%s' "$suffix" | sed -nE 's/.*[Cc]hapter[ _-]*[0-9]+[ _-]*([A-Za-z])([^A-Za-z0-9]|$).*/\1/p')"
				if [[ -n "$letter" ]]; then
					letter="$(printf '%s' "$letter" | tr 'A-Z' 'a-z')"
					part=$(( $(printf '%d' "'$letter") - $(printf '%d' "'a") + 1 ))
				fi
			fi
		else
			track="$(printf '%s' "$suffix" | sed -nE 's/.*[^0-9]([0-9]+)[A-Za-z]*$/\1/p')"
			part=""
		fi

		printf '%01d\t%05d\t%05d\t%05d\t%s\n' \
			"$kind" "$((10#${disc:-0}))" "$((10#${track:-0}))" "$((10#${part:-0}))" "$f"
	done | sort -t $'\t' -k1,1n -k2,2n -k3,3n -k4,4n -k5,5Vf | cut -f5-
) ); unset IFS

# ---- work out the book title / output name -----------------------------------
if [[ -z "$TITLE" ]]; then
	# strip a trailing " - 001" / " 001" / "-001" style number from file 1
	TITLE="$(printf '%s' "${mp3s[0]%.*}" | sed -E 's/[[:space:]]*-?[[:space:]]*[0-9]+$//')"
	[[ -n "$TITLE" ]] || TITLE="$(basename "$PWD")"
fi
OUT="${2:-${TITLE}.m4b}"
OUT="${OUT%.m4b}.m4b"

# ---- pick the best available AAC encoder ------------------------------------
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' aac_at '; then
	AAC_ARGS=( -c:a aac_at -b:a 64k -ac 1 )   # Apple AudioToolbox - best at low bitrate
else
	AAC_ARGS=( -c:a aac -b:a 64k -ac 1 )
fi

# ---- optional cover art -----------------------------------------------------
COVER=""
for c in cover.jpg cover.jpeg cover.png folder.jpg folder.png; do
	match="$(find . -maxdepth 1 -iname "$c" -print -quit)"
	if [[ -n "$match" ]]; then
		COVER="${match#./}"
		break
	fi
done

# ---- build the concat list and the chapter metadata -----------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LIST="$WORK/concat.txt"
META="$WORK/metadata.txt"

: > "$LIST"
{
	echo ';FFMETADATA1'
	echo "title=${TITLE}"
	echo "album=${TITLE}"
	echo "genre=Audiobook"
	echo "media_type=2"          # 2 = Audiobook (Apple Books / Music)
	[[ -n "$AUTHOR" ]] && echo "artist=${AUTHOR}"
	[[ -n "$AUTHOR" ]] && echo "album_artist=${AUTHOR}"
	[[ -n "$AUTHOR" ]] && echo "composer=${AUTHOR}"
	[[ -n "$YEAR"   ]] && echo "date=${YEAR}"
} > "$META"

fmt_time() {
	local ms=$1 s h m
	s=$((ms / 1000))
	h=$((s / 3600))
	m=$(((s % 3600) / 60))
	s=$((s % 60))
	printf '%02d:%02d:%02d' "$h" "$m" "$s"
}

if (( DRY_RUN )); then
	printf '%-4s  %-12s  %-8s  %-8s  %s\n' "#" "Chapter" "Start" "Dur" "File"
fi

start_ms=0
n=0
for f in "${mp3s[@]}"; do
	n=$((n + 1))
	abs="$PWD/$f"
	esc=${abs//\'/\'\\\'\'}                       # escape ' for the concat demuxer
	printf "file '%s'\n" "$esc" >> "$LIST"

	dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")"
	dur_ms="$(awk -v d="$dur" 'BEGIN{printf "%d", (d*1000)+0.5}')"
	end_ms=$((start_ms + dur_ms))

	# chapter title: sequential position in playback order (handles multi-disc
	# folders where each disc restarts its own track numbering, e.g.
	# Disc1_Track01, Disc2_Track01 would otherwise both become "Chapter 1")
	title="Chapter $n"

	if (( DRY_RUN )); then
		printf '%-4s  %-12s  %-8s  %-8s  %s\n' \
			"$n" "$title" "$(fmt_time "$start_ms")" "$(fmt_time "$dur_ms")" "$f"
	fi

	{
		echo '[CHAPTER]'
		echo 'TIMEBASE=1/1000'
		echo "START=${start_ms}"
		echo "END=${end_ms}"
		echo "title=${title}"
	} >> "$META"

	start_ms=$end_ms
done

echo
echo "Title     : $TITLE"
[[ -n "$AUTHOR" ]] && echo "Author    : $AUTHOR"
[[ -n "$YEAR"   ]] && echo "Year      : $YEAR"
echo "Chapters  : $n"
echo "Encoder   : ${AAC_ARGS[1]} @ 64k mono"
[[ -n "$COVER" ]] && echo "Cover     : $COVER"
echo "Output    : $PWD/$OUT"
echo

if (( DRY_RUN )); then
	echo "(dry run -- no file written)"
	exit 0
fi

# ---- encode --------------------------------------------------------------
if [[ -n "$COVER" ]]; then
	ffmpeg -hide_banner -y \
		-f concat -safe 0 -i "$LIST" \
		-f ffmetadata -i "$META" \
		-i "$COVER" \
		-map 0:a -map 2:v \
		-map_metadata 1 -map_chapters 1 \
		"${AAC_ARGS[@]}" \
		-c:v mjpeg -disposition:v:0 attached_pic \
		-movflags +faststart \
		-f mp4 "$OUT"
else
	ffmpeg -hide_banner -y \
		-f concat -safe 0 -i "$LIST" \
		-f ffmetadata -i "$META" \
		-map 0:a \
		-map_metadata 1 -map_chapters 1 \
		"${AAC_ARGS[@]}" \
		-movflags +faststart \
		-f mp4 "$OUT"
fi

echo
echo "Done -> $PWD/$OUT"
