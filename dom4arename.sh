#!/usr/bin/env bash


if [[ ! -f "$1" ]]
then
  "FAIL: no such file $1"
  exit 1
fi
title="$(mediainfo "$1"|grep -E '^Title\s*:'|cut -d':' -f2-|sed -e 's/^ //'|head -1)"

[[ "$1" =~ .mp3$ ]] && mv "$1" "${title}.mp3"
[[ "$1" =~ .m4a$ ]] && mv "$1" "${title}.m4a"
[[ "$1" =~ .m4b$ ]] && mv "$1" "${title}.m4b"
