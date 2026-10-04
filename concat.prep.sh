#!/usr/bin/env bash

. ~/bashrc.mk

IFS=$"\n"

rm -rf */*nfo */*trickplay */*jpg >/dev/null 2>&1
for i in */*
do
    mv "$i" "${i/\//}" >/dev/null 2>&1
done
#for i in $(find . -type d -depth 1)
#do
#    mkbanner "$i"
#    for f in ${i}*/*.mp4 ${i}*/*.webm ${i}*/*.avi ${i}*/*.ts
#    do
#        mv "${f}" "${i}${f##*/}"
#    done
#    if ls ${i}*/*.srt >/dev/null 2>&1
#    then
#        for f in ${i}*/*.srt
#        do
#            mv "${f}" "${i}${f##*/}"
#        done
#    fi
#    if ls ${i}*/*.vtt >/dev/null 2>&1
#    then
#        for f in ${i}*/*.vtt
#        do
#            mv "${f}" "${i}${f##*/}"
#        done
#    fi
#done
rmdir * >/dev/null 2>&1
mkbanner "dirs"
find . -type d
