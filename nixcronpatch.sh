#!/bin/sh
# Installs the OS's package updates, unattended, from root's crontab. Covers
# the OSes mynixpatchall in .bashrc patches, with the same commands made
# non-interactive:
#   Linux        apt (Debian, Ubuntu), dnf (Fedora, RHEL, Amazon Linux), apk (Alpine)
#   FreeBSD      pkg
#   OpenBSD      syspatch, fw_update, pkg_add
#   NetBSD       pkgin
#   OpenIndiana  pkg (an OS update goes into a new boot environment)
#   Haiku        pkgman
# Only the OS's packages: Homebrew, pkgsrc next to another OS's packages, and
# pip/npm/etc. (patchmods) are left to mynixpatchall. It never reboots; a
# kernel or OS update takes effect at the next reboot.
#
# POSIX sh, not bash: bash isn't in /bin on the BSDs, and cron's PATH may not
# find it.
#
# Example root crontab line (starts at 01:00, then waits up to 8 hours):
#   0 1 * * * /path/to/nixcronpatch.sh >/var/log/nixcronpatch.log 2>&1

PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/libexec:/usr/local/bin:/usr/local/sbin:/usr/pkg/bin:/usr/pkg/sbin:/boot/system/bin
export PATH

if [ "$(id -u)" -ne 0 ]
then
    echo "FAIL: run as root (from root's crontab)"
    exit 1
fi

# Wait a random time, up to 8 hours, so machines don't all patch at once
rand=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')
case "$rand" in
    ''|*[!0-9]*) rand=$(awk 'BEGIN { srand(); print int(rand() * 2147483647) }') ;;
esac
mysleep=$((rand % 28800))
echo "sleeping $mysleep"
sleep "$mysleep"

# Ends the named programs left hung from an earlier run, like the dnf branch
# does: asks them to stop, then kills what's left 5 seconds later. Matched by
# command line (the program, or a script run by perl, ksh, sh, bash or
# python), since OpenBSD's pkg_add, syspatch and fw_update and OpenIndiana's
# pkg are scripts, so their process name is the interpreter's.
killstale()
{
    names=$(echo "$*" | tr ' ' '|')
    re="^(([^ ]*/)?(python[0-9.]*|perl|ksh|sh|bash)( -[^ ]+)* )?([^ ]*/)?($names)( |\$)"
    if command -v pkill >/dev/null 2>&1
    then
        if pkill -f "$re"
        then
            echo "stopped a hung $*"
            sleep 5
            pkill -9 -f "$re"
        fi
    elif command -v killall >/dev/null 2>&1
    then
        # Haiku: killall by name only
        killall "$@" 2>/dev/null && sleep 5 && killall -9 "$@" 2>/dev/null
    else
        echo "no pkill or killall: a hung $* isn't stopped"
    fi
}

os=$(uname -s 2>/dev/null)
echo "patching $os $(uname -r 2>/dev/null) on $(hostname) at $(date)"
fail=0

case "$os" in
    Linux)
        if command -v apt-get >/dev/null 2>&1
        then
            # A hung apt, dpkg or unattended-upgrades from an earlier run is
            # stopped, then dpkg --configure -a finishes what it left half
            # installed. Anything else holding the lock is waited for, up
            # to an hour.
            killstale apt apt-get dpkg unattended-upgrade unattended-upgrades
            DEBIAN_FRONTEND=noninteractive
            export DEBIAN_FRONTEND
            set -- -y -o DPkg::Lock::Timeout=3600 \
                -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
            dpkg --configure -a || fail=1
            apt-get "$@" update || fail=1
            apt-get "$@" dist-upgrade || fail=1
            apt-get "$@" autoremove || fail=1
            apt-get "$@" clean
        elif command -v dnf >/dev/null 2>&1
        then
            # A dnf left over from an earlier run that hung
            pkill dnf
            sleep 5
            pkill -9 dnf
            dnf clean all
            dnf update -y || fail=1
            dnf clean all
        elif command -v apk >/dev/null 2>&1
        then
            killstale apk
            apk update || fail=1
            apk upgrade || fail=1
        else
            echo "FAIL: no apt, dnf, or apk found"
            fail=1
        fi
        ;;
    FreeBSD)
        ASSUME_ALWAYS_YES=yes
        export ASSUME_ALWAYS_YES
        killstale pkg pkg-static
        pkg update || fail=1
        pkg upgrade -y || fail=1
        ;;
    OpenBSD)
        killstale syspatch fw_update pkg_add
        # Exit 2 means no patch was installed. After one that did, run it
        # again: syspatch can update itself first and stop there.
        syspatch
        rc=$?
        if [ "$rc" -eq 0 ]
        then
            syspatch
            rc=$?
        fi
        [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || fail=1
        fw_update || fail=1
        # -I: never ask; an update with several candidates is skipped
        pkg_add -u -I -x || fail=1
        ;;
    NetBSD)
        killstale pkgin pkg_add
        pkgin -y update || fail=1
        pkgin -y upgrade || fail=1
        # -y doesn't apply to autoremove, so answer its prompt here
        yes | pkgin autoremove
        pkgin clean
        ;;
    SunOS)
        killstale pkg
        # Exit 4 means there was nothing to update
        pkg update
        rc=$?
        case $rc in
            0) ;;
            4) echo "No updates available" ;;
            *) echo "FAIL: pkg update exited with $rc"; fail=1 ;;
        esac
        # beadm flags: N = active now, R = active on reboot
        be=$(beadm list -H 2>/dev/null | awk -F';' '$3 ~ /R/ && $3 !~ /N/ { print $1 }')
        [ -n "$be" ] && echo "REBOOT to switch to the updated boot environment $be"
        ;;
    Haiku)
        killstale pkgman
        pkgman refresh || fail=1
        pkgman update -y || fail=1
        pkgman full-sync -y || fail=1
        ;;
    *)
        echo "FAIL: nixcronpatch.sh is for Linux (apt, dnf, apk), FreeBSD, OpenBSD, NetBSD, OpenIndiana and Haiku, not $os"
        fail=1
        ;;
esac

sync
echo "finished at $(date)"
exit "$fail"
