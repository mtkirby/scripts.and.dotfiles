#!/usr/bin/env bash
# Make .ai.srt subtitles for the videos one folder down in each directory given.
# Usage: doshowsubs.sh /Volumes/movie1 /Volumes/movie2 ...

# shellcheck source=/dev/null # for mkbanner
. ~/.bashrc

if (( $# == 0 ))
then
    echo "Usage: ${0##*/} dir [dir ...]" >&2
    exit 1
fi

# nullglob: a directory with no videos gives no files, not the pattern itself
shopt -s nullglob extglob

for d in "$@"
do
    for i in "${d}"/*.@(avi|mkv|mp4|m4v)
    do
        mkbanner "$d" "#" red
        mkbanner "$i" "-" yellow
        # Strip the extension only; a pattern match could hit ".mkv" earlier in the path
        ls "${i%.*}.srt" "${i%.*}.ai.srt" || ~/scripts/dosubtitles.sh "$i"
    done
done
