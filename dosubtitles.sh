#!/usr/bin/env bash
# Usage: dosubtitles.sh <video> ["prompt"]
# The optional prompt names people, places and jargon in the video so whisper
# spells them right, e.g. "Star Trek: Picard. Riker, Romulan, Starfleet."
# Models (in ~/.local/share/whisper-models):
#   curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin
#   (or ggml-large-v3-turbo.bin: several times faster, less accurate; used if large-v3 is absent)
#   curl -LO https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin

set -x

renice -n 20 $$

export IFS=$'\n'

myvid="$1"
prompt="$2"
models=~/.local/share/whisper-models
# Most accurate first. turbo keeps large-v3's audio encoder but cuts its text
# decoder from 32 layers to 4: several times faster, more errors on hard audio
for model in "$models/ggml-large-v3.bin" "$models/ggml-large-v3-turbo.bin"
do
    [[ -f "$model" ]] && break
done
# Voice activity detection skips music and silence, where large models invent words
vad="$models/ggml-silero-v6.2.0.bin"
# Strip the extension only; a pattern match could hit ".mkv" earlier in the path
mybase="${myvid%.*}"
tmpwav="/Volumes/shared/tmp/dosubtitles.$$.wav"


# skip if the video already has subtitles, or if a .srt file already exists
#count=$(ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$myvid" | wc -l | tr -d ' ')
#if [[ $count != 0 ]] \
#|| [[ -f "${mybase}.srt" ]]
#then
#    echo "Already has subtitles: $myvid"
#    exit 0
#fi

if [[ -f "${mybase}.ai.srt" ]]
then
    echo "Already has subtitles: $myvid"
    exit 0
fi

if [[ ! -f "$model" ]]
then
    echo "FAIL: $model not found; see the download commands at the top of $0"
    exit 1
fi

# 5.1/7.1: dialogue lives in the center channel; a full downmix buries it under music
channels=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$myvid")
af=()
(( channels >= 6 )) && af=(-af "pan=mono|c0=FC")

# Leave beam search at its default 5: -bs 8 -bo 8 with --vad starts a line where
# the previous speech ended instead of where it begins, showing it seconds early
opts=(-m "$model" -l en -t 8)
[[ -f "$vad" ]] && opts+=(--vad -vm "$vad")
# Each 30s window is normally primed with the previous window's text, so one bad
# line can repeat for the rest of the file. -mc caps that context in tokens; 0
# drops it, but also drops the prompt. With a prompt, repeat it in every window
# and size -mc to about the prompt alone (English runs 3-4 characters a token).
if [[ -n "$prompt" ]]
then
    opts+=(--prompt "$prompt" --carry-initial-prompt -mc $(( ${#prompt} / 3 + 2 )))
else
    opts+=(-mc 0)
fi

# -map 0:a:0: the first audio track, not one ffmpeg ranks higher such as commentary
ffmpeg -i "$myvid" -map 0:a:0 -vn "${af[@]}" -f wav -ar 16000 -ac 1 -c:a pcm_s16le "$tmpwav"
whisper-cli "${opts[@]}" -f "$tmpwav" -osrt -of "${mybase}.ai"

rm -f "$tmpwav"
