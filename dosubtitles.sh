#!/usr/bin/env bash

set -x

renice -n 20 $$

export IFS=$'\n'

myvid="$*"
mybase="${myvid/\.m[4pk][4v]/}"
tmpwav="/Volumes/shared/tmp/dosubtitles.$$.wav"

count=$(ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$myvid" | wc -l | tr -d ' ')

#if [[ $count != 0 ]] \
#|| [[ -f "${mybase}.srt" ]]
#then
#    echo "Already has subtitles: $myvid"
#    exit 0
#fi

if [[ -f "${mybase}.srt" ]]
then
    echo "Already has subtitles: $myvid"
    exit 0
fi

ffmpeg -i "$myvid" -vn -f wav -ar 16000 -ac 1 -c:a pcm_s16le "$tmpwav"
whisper-cli -m ~/.local/share/whisper-models/ggml-base.en.bin -f "$tmpwav" -osrt -of "$mybase"

rm -f "$tmpwav"
