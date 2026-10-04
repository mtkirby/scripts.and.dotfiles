#!/usr/bin/env bash

IFS=$'\n'
renice -n 20 $$


while pgrep -q ffmpeg
do
    pwd
    mysleep=$(( (($RANDOM * $RANDOM ) % 300) + (($RANDOM * $RANDOM ) % 300) + 90 ))
    echo "sleeping $mysleep"
    sleep $mysleep
done

name="$(basename `pwd`)"
~/Movies/concat.prep.sh
~/Movies/concat.sh . "${name}.mkv" && mv "${name}.mkv" ../ && ls -lh ../"${name}.mkv"

false
