#!/bin/bash
# shellcheck shell=bash disable=SC2001
# 20261004 kirby
# usage: dnsfileserve.sh <zonefile>
# rebuilds <zonefile> from <zonefile>.template, adding one gzip+base64 TXT
# record per file in $filesdir plus a "list" record naming them all.
# fetch a file with:
#   dig +short TXT name.zone | tr -d '" \n' | base64 -d | gunzip

set -o pipefail

workdir="/var/named/chroot/var/named"
chroot="/var/named/chroot"
namedconf="/etc/named.conf"   # path inside the chroot
filesdir="${workdir}/files"
maxb64=60000                  # dns messages max out at 64k, leave room for overhead
keep=10                       # timestamped zone copies to keep

if [[ $# -ne 1 ]]
then
  echo "usage: $0 <zonefile>"
  exit 1
fi
zonefile=$1
zonetemplate="${zonefile}.template"
failsafe="${zonefile}.failsafe"
previous="${zonefile}.prev"

if ! cd "$workdir"
then
  echo "bad workdir $workdir"
  exit 1
fi
if [[ ! -f "$zonefile" ]]
then
  echo "supply zonefile or bad zonefile $zonefile"
  exit 1
fi
if [[ ! -f "$zonetemplate" ]]
then
  echo "template file $zonetemplate does not exist"
  exit 1
fi
if [[ ! -f "$failsafe" ]]
then
  echo "failsafe file $failsafe does not exist"
  exit 1
fi
if [[ ! -d "$filesdir" ]]
then
  echo "files dir $filesdir does not exist"
  exit 1
fi

# serial must go up every run or secondaries ignore the change,
# so bump past the last one if we run twice in the same minute
myserial=$(date +%y%m%d%H%M)
lastserial=$(printf "%s\n" "${zonefile}".[0-9]* | sed -e 's/.*\.//' | grep -E '^[0-9]+$' | sort -n | tail -1)
if [[ -n "$lastserial" && "$myserial" -le "$lastserial" ]]
then
  myserial=$((lastserial + 1))
fi
newzonefile="${zonefile}.$myserial"

if ! sed -e "s/MYSERIAL/$myserial/" "$zonetemplate" > "$newzonefile"
then
  echo "could not write $newzonefile"
  exit 1
fi

names=()
for path in "$filesdir"/*
do
  [[ -f "$path" ]] || continue
  file=${path##*/}
  if [[ ! "$file" =~ ^[A-Za-z0-9_-]{1,63}(\.[A-Za-z0-9_-]{1,63})*$ ]] || (( ${#file} > 200 ))
  then
    echo "skipping $file: not a valid dns name"
    continue
  fi
  if [[ "$file" == "list" ]]
  then
    echo "skipping $file: name is reserved for the file list"
    continue
  fi
  if ! encoded=$(gzip -9n < "$path" | base64 -w75)
  then
    echo "skipping $file: gzip/base64 failed"
    continue
  fi
  if (( ${#encoded} > maxb64 ))
  then
    echo "skipping $file: ${#encoded} bytes encoded, max is $maxb64"
    continue
  fi
  {
    echo "$file IN TXT (\"\""
    sed -e 's/.*/  "&"/' <<< "$encoded"
    echo '  "")'
  } >> "$newzonefile"
  names+=("$file")
done

# a single TXT string is capped at 255 bytes, so spread the list over several.
# each chunk ends in a space so names don't run together when joined
{
  printf 'list IN TXT ('
  chunk=""
  for file in "${names[@]}"
  do
    if (( ${#chunk} + ${#file} + 1 > 255 ))
    then
      printf '"%s"\n  ' "$chunk"
      chunk=""
    fi
    chunk+="$file "
  done
  printf '"%s"\n  "")\n' "$chunk"
} >> "$newzonefile"

# roll back to the zone that was working, not just the failsafe
if ! cp -p "$zonefile" "$previous"
then
  echo "could not back up $zonefile to $previous"
  exit 1
fi

# cat instead of mv keeps the zone file's owner, mode and selinux label
cat "$newzonefile" > "$zonefile"

# check config and zones before touching named so a bad zone never takes dns down
if ! checkout=$(named-checkconf -t "$chroot" -z "$namedconf" 2>&1)
then
  echo "$checkout"
  echo "FAIL: named-checkconf rejected new zone, restored $previous"
  cat "$previous" > "$zonefile"
  exit 1
fi

# reload picks up the change without dropping service, restart only if rndc can't reach named
if rndc reload > /dev/null || systemctl restart named-chroot
then
  echo "loaded serial $myserial with ${#names[@]} files"
  ps -efwww|head -1
  ps -efwww|grep -v grep |grep named
  printf "%s\n" "${zonefile}".[0-9]* | head -n -"$keep" | xargs -r rm -f --
else
  echo "FAIL FAIL FAIL FAIL FAIL FAIL FAIL FAIL"
  cat "$previous" > "$zonefile"
  if ! systemctl restart named-chroot
  then
    echo "previous zone failed too, using $failsafe"
    cat "$failsafe" > "$zonefile"
    systemctl restart named-chroot
  fi
  exit 1
fi
