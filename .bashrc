# 20261017 Kirby
# shellcheck shell=bash disable=SC1090,SC1091,SC2009

##################################################
# SETUP PATH
##################################################
export HOME=${HOME:-~}
export oldPATH=$PATH
unset PATH
#export PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/libexec:/usr/local/bin:/usr/local/sbin:$HOME/.local/bin:$HOME/bin

for i in \
    $HOME/.local/bin \
    $HOME/bin \
    $HOME/scripts \
    $HOME/perl5/bin \
    /opt/homebrew/bin \
    /opt/homebrew/sbin \
    /opt/homebrew/libexec \
    /home/linuxbrew/.linuxbrew/bin \
    /home/linuxbrew/.linuxbrew/sbin \
    /home/linuxbrew/.linuxbrew/libexec \
    /opt/local/bin \
    /opt/local/sbin \
    /opt/local/libexec \
    /usr/pkg/bin \
    /usr/pkg/sbin \
    /usr/pkg/libexec \
    /opt/pkg/bin \
    /opt/pkg/sbin \
    /opt/pkg/libexec \
    /bin \
    /usr/bin \
    /sbin \
    /usr/sbin \
    /usr/libexec \
    /usr/local/bin \
    /usr/local/sbin 
do
    [[ -d "$i" ]] && export PATH="${PATH:+${PATH}:}${i}"
done

IFS=: read -ra dirs <<< "$oldPATH"
for i in "${dirs[@]}"
do
    if [[ ":$PATH:" != *":$i:"* ]]
    then
        PATH="${PATH}:${i}"
    fi
done

##################################################
# SETUP LD_LIBRARY_PATH
##################################################
export oldLD_LIBRARY_PATH=$LD_LIBRARY_PATH

newldpath="/lib64:/usr/lib64:/lib:/usr/lib"
if [[ -e /etc/ld.so.conf ]]
then
    while IFS= read -r i
    do
        newldpath="${newldpath}:${i}"
    done < <(grep -hE '^/' /etc/ld.so.conf /etc/ld.so.conf.d/* 2>/dev/null)
fi
for i in \
    $HOME/.local/lib64 \
    $HOME/.local/lib \
    /opt/homebrew/lib64 \
    /opt/homebrew/lib \
    /opt/local/lib64 \
    /opt/local/lib \
    /usr/pkg/lib64 \
    /usr/pkg/lib
do
    [[ -d "$i" ]] && newldpath="$newldpath:$i"
done
export LD_LIBRARY_PATH=$newldpath

##################################################
# ENV VARS
##################################################
export USER=${USER:-$LOGNAME}

if [[ "$USER" == "root" ]] \
|| [[ "$USER" == "Administrator" ]]
then
    umask 022
else
    umask 077
fi

export VISUAL=vi
export EDITOR=vi

if [[ -d /opt/homebrew ]]
then
    eval "$(PATH=/usr/bin:/bin /opt/homebrew/bin/brew shellenv bash |grep -v 'export PATH=')"
fi

if [[ -d "${HOME}/perl5" ]]
then
    export PERL5LIB="${HOME}/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"
    export PERL_LOCAL_LIB_ROOT="${HOME}/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"
    export PERL_MB_OPT="--install_base \"${HOME}/perl5\""
    export PERL_MM_OPT="INSTALL_BASE=${HOME}/perl5"
fi

##################################################
# Non-interactive shells (ssh host cmd, scp, rsync) only need the environment above
[[ $- == *i* ]] || return

##################################################
if command -v bat >/dev/null 2>&1
then
    if command -v less >/dev/null 2>&1
    then
        export BAT_PAGER="less -RFX"
    fi
    if bat --list-themes 2>&1 |grep -q Catppuccin
    then
        export BAT_THEME='Catppuccin Mocha'
    elif bat --list-themes 2>&1 |grep -q zenburn
    then
        export BAT_THEME='zenburn'
    elif bat --list-themes 2>&1 |grep -q 1337
    then
        export BAT_THEME='1337'
    else
        export BAT_THEME='ansi'
    fi
fi

##################################################
# SHELL OPTS
##################################################
set -o vi         # vi shell mode
set -o pipefail   # if any command in pipefile fails, return failure status
shopt -s dotglob >/dev/null 2>&1
shopt -s checkjobs >/dev/null 2>&1

##################################################
# ALIASES
##################################################
if grep --version 2>&1 |grep -q GNU
then
    alias grep='grep --color=auto -a '
    alias egrep='grep -E --color=auto -a '
fi

if cp --help -v >/dev/null 2>&1 \
&& mv --help -v >/dev/null 2>&1 \
&& rm --help -v >/dev/null 2>&1 
then
    alias cp="cp -v"
    alias mv="mv -v"
    alias rm="rm -v"
elif [[ -f /opt/homebrew/bin/gcp ]] \
&&   [[ -f /opt/homebrew/bin/gmv ]] \
&&   [[ -f /opt/homebrew/bin/grm ]]
then
    alias cp="/opt/homebrew/bin/gcp -v"
    alias mv="/opt/homebrew/bin/gmv -v"
    alias rm="/opt/homebrew/bin/grm -v"
elif [[ -f /usr/local/bin/gcp ]] \
&&   [[ -f /usr/local/bin/gmv ]] \
&&   [[ -f /usr/local/bin/grm ]]
then
    alias cp="/usr/local/bin/gcp -v"
    alias mv="/usr/local/bin/gmv -v"
    alias rm="/usr/local/bin/grm -v"
elif [[ -f /opt/local/bin/gcp ]] \
&&   [[ -f /opt/local/bin/gmv ]] \
&&   [[ -f /opt/local/bin/grm ]]
then
    alias cp="/opt/local/bin/gcp -v"
    alias mv="/opt/local/bin/gmv -v"
    alias rm="/opt/local/bin/grm -v"
else
    unalias cp >/dev/null 2>&1
    unalias mv >/dev/null 2>&1
    unalias rm >/dev/null 2>&1
fi

alias ll='"ls" -Fl'
alias l='"ls" -1AF'
if /bin/ls -FAbd --color=never / >/dev/null 2>&1
then
    alias ls='ls -FAb --color=never'
elif /bin/ls -FAbd >/dev/null 2>&1
then
    alias ls='ls -FAb'
else
    alias ls='ls -FA'
fi
alias dusk='du -sk * |sort -k1 -n'
alias myltrace='ltrace -Sif '
alias mystrace='strace -yy -s 1024 -a 80 -f -v -y '

alias ifsd="export IFS=$' \t\n'"
alias ifsn="export IFS=$'\n'"

if ps -eww -o user,pid,ppid,pgid,stat,tty,nice,pcpu,pmem,stime,command >/dev/null 2>&1
then
    alias psa='ps -eww -o user,pid,ppid,pgid,stat,tty,nice,pcpu,pmem,stime,command'
elif ps -axwww -o user,pid,ppid,%cpu,%mem,vsz,rss,tt,stat,start,etime,time,command >/dev/null 2>&1
then
    alias psa='ps -axwww -o user,pid,ppid,%cpu,%mem,vsz,rss,tt,stat,start,etime,time,command'
else
    alias psa='ps -ef'
fi
alias pslxc='ps -eww -o lxc,cgroup,user,pid,ppid,nice,pcpu,pmem,command'

alias sc='systemctl -l --no-pager'
alias jc='journalctl -xa --no-pager'
alias s='sudo'
alias si='sudo -i'
alias tidyperl='perltidy -ce -l=240 '
alias zrm='scrub -S -pfillzero -f '
command -v vim >/dev/null 2>&1 && alias vi=vim

command -v rdap >/dev/null 2>&1 && alias whois='rdap'



##################################################
# HISTORY
##################################################
#mytty=`tty` >/dev/null 2>&1
#export SESSION_HIST_DIR="$HOME/.bash_histories"
#[[ ! -d "$SESSION_HIST_DIR" ]] && mkdir "$SESSION_HIST_DIR" >/dev/null 2>&1
#history -w
#history -c
#for histfile in $('ls' -tr "${SESSION_HIST_DIR}"/* 2>/dev/null)
#do
    #history -r "$histfile" >/dev/null 2>&1
#done
#export HISTFILE="$HOME/.bash_histories/$(date +%Y%m%d).$(tty |tr '/' '_')"
export HISTFILE=~/.bash_history
#export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S # " 
export HISTTIMEFORMAT="%Y%m%d.%H:%M:%S# " 
export HISTSIZE=100000
export HISTCONTROL=ignoredups:erasedups:ignorespace
shopt -s histappend
shopt -s histverify
shopt -s cmdhist

##################################################
# PROMPT
##################################################
#Color,Regular Code,Bold/Bright Code
#Black,30m,30;1m
#Red,31m,31;1m
#Green,32m,32;1m
#Yellow,33m,33;1m
#Blue,34m,34;1m
#Magenta,35m,35;1m
#Cyan,36m,36;1m
#White,37m,37;1m

rstcolor='\[\e[0m\]'     # Text Reset

#if [[ "$DESKTOP_SESSION" == "xfce" ]] \
#|| [[ "$OS" == "Windows_NT" ]]

case "$USER" in
    "root")          pscolor='\[\e[93;1;40m\]' ; hcolor='\[\e[30;101m\]' ;;
    "Administrator") pscolor='\[\e[93;1;40m\]' ; hcolor='\[\e[30;101m\]' ;;
    "pgsql")         pscolor='\[\e[92;1;40m\]' ; hcolor='\[\e[30;102m\]' ;;
    *)               pscolor='\[\e[96;1;40m\]' ; hcolor='\[\e[30;106m\]' ;;
esac

mkpromptcmd() {
    local last_status=$?
    #local last_cmd
    local load
    #last_cmd=$(history 1)

    history -a >/dev/null 2>&1

    ERROR_MSG=""
    # error code 130 is from ctrl-c
    #if [[ $last_status -ne 0 && $last_status -ne 130 ]]
    if [[ $last_status -ne 0 ]] \
    && [[ $last_status -ne 130 ]]
    then
        local err_text="${ERR_MAP[$last_status]}"
# disabled because of bash: child setpgid (22926 to 22926): Operation not permitted
#        if [[ -z "$err_text" ]]
#        then
#            if echo "$last_cmd" |grep -qE 'aws |AWS'
#            then
#                err_text="${AWS_ERR_MAP[$last_status]}"
#            elif echo "$last_cmd" |grep -qE 'curl |CURL'
#            then
#                err_text="${CURL_ERR_MAP[$last_status]}"
#            fi
#        fi
        #ERROR_MSG=$(echo -e "\a\033[5;30;1;101m[ERR:$last_status]\033[0m ")
        ERROR_MSG=$(echo -e "\n  \e[0m\a\e[5;30;101m## ERR:${last_status}${err_text} ##\e[0m")
        TAB_TITLE=$(echo -ne "\033]0;❌ ERR:$last_status $USER@$HOSTNAME\007")
    else
        TAB_TITLE=$(echo -ne "\033]0;$USER@$HOSTNAME\007")
    fi
    # minix console doesn't understand the title escape and prints it as text
    [[ "$TERM" == "minix" ]] && TAB_TITLE=''

# disabled because of bash: child setpgid (22926 to 22926): Operation not permitted
#    if [[ "$AWS_PROFILE" != "$myoldawsprofile" ]] \
#    && [[ "$AWS_PROFILE" != "localstack" ]] \
#    && echo "$last_cmd" |grep -qE 'aws |AWS'
#    then
#        myawsrole=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null | cut -d'/' -f2 |cut -d':' -f6 2>/dev/null)
#
#        myawsaccountname=$(aws account get-account-information 2>/dev/null | jq -r '.AccountName' 2>/dev/null)
#
#        PSAWS=$(echo -e "\n\033[93;1;40m  ## ${AWS_PROFILE}: ${myawsrole} @ ${myawsaccountname} @ ${AWS_REGION:-$AWS_DEFAULT_REGION} ##\033[0m ")
#
#        myoldawsprofile="$AWS_PROFILE"
#    fi

    #if [[ "$ihavegit" == "YES" ]] \
    #&& echo "$last_cmd" |grep -qE 'git |GIT'
    #then
    #    dogitps
    #fi

    if [[ -f ~/psalert ]]
    then
        PSALERT=$(echo -e "\033[93;1;40m  ## $(cat ~/psalert) ##\033[0m ")
    else
        PSALERT=''
    fi

    if [[ -e /proc/loadavg ]]
    then
        load=$(awk '{print $1}' /proc/loadavg)
    elif sysctl vm.loadavg >/dev/null 2>&1
    then
        load=$(sysctl vm.loadavg |awk '{print $3}')
    else
        load=$(uptime |awk '{print $10}')
    fi
    #LOAD_INFO=$(echo -e "[L:$load] ")
    LOAD_INFO=$(echo -e "${load}${PSCPUCOUNT} ")

    if [[ ${oldcols:-0} != "${COLUMNS}" ]]
    then
        mycol=${COLUMNS:-55}
        #mycol=$((mycol - 5))
        oldcols=$COLUMNS
        printf -v PSBANNER '%*s' "$mycol" ''
        PSBANNER="${PSBANNER// /-}"
    fi
}

if [[ -e /proc/cpuinfo ]]
then
    PSCPUCOUNT="/$(grep -c -E '^processor' /proc/cpuinfo)"
elif sysctl hw.ncpu 2>/dev/null |grep -q hw.ncpu
then
    PSCPUCOUNT="/$(sysctl -n hw.ncpu)"
else
    PSCPUCOUNT=""
fi


PROMPT_COMMAND=mkpromptcmd

shicon=""
if sysctl machdep.cpu.brand_string 2>/dev/null |grep -q Apple
then
    shicon="🍎"
fi
[[ $HOSTNAME =~ vps ]] && shicon="☁️"
[[ $HOSTNAME =~ hostinger ]] && shicon="☁️"
[[ $HOSTNAME =~ nas ]] && shicon="💾"
[[ $HOSTNAME =~ kali ]] && shicon="🔥"
[[ $HOSTNAME =~ studio ]] && shicon="🍎🏠"
[[ $HOSTNAME =~ nomad ]] && shicon="🍎💻"
[[ $HOSTNAME =~ [rv][123456789]\.mk\.lan ]] && shicon="🔩"

declare -A ERR_MAP >/dev/null 2>&1
ERR_MAP=(
    [1]=":General Error"
    [2]=":Syntax/Command Error"
    [3]=":ESRCH No Such Process"
    [4]=":EINTR Interrupted System Call"
    [5]=":EIO I/O Error"
    [8]=":ENOEXEC Exec Format Error"
    [9]=":EBADF Bad File Descriptor"
    [10]=":ECHILD No Child Processes"
    [12]=":ENOMEM Out Of Memory"
    [13]=":EACCES Permission Denied"
    [14]=":EFAULT Bad Address"
    [15]=":ENOTBLK Block Device Required"
    [16]=":EBUSY Device/Resource Busy"
    [17]=":EEXIST File Exists"
    [18]=":EXDEV Cross-Device Link"
    [19]=":ENODEV No Such Device"
    [20]=":ENOTDIR Not A Directory"
    [21]=":EISDIR Is A Directory"
    [22]=":EINVAL Invalid Arg"
    [23]=":ENFILE File Table Overflow"
    [24]=":EMFILE Too Many Open Files"
    [25]=":ENOTTY Inappropriate ioctl"
    [26]=":ETXTBSY Text File Busy"
    [27]=":EFBIG File Too Large"
    [29]=":ESPIPE Illegal Seek"
    [30]=":EROFS Read-Only File System"
    [31]=":EMLINK Too Many Links"
    [32]=":EPIPE Broken Pipe"
    [33]=":EDOM Numerical Arg Out Of Domain"
    [34]=":ERANGE Numerical Result Out Of Range"
    [126]=":Permission Denied (Exec)"
    [127]=":Command Not Found"
    [128]=":Invalid Exit / Git Error"
    [129]=":SIGHUP (Hangup)"
    [130]=":SIGINT (Ctrl+C)"
    [131]=":SIGQUIT (Ctrl+\)"
    [132]=":SIGILL Illegal Instruction"
    [133]=":SIGTRAP Trace/Breakpoint Trap"
    [134]=":SIGABRT Abort"
    [136]=":SIGFPE Floating Point Exception"
    [137]=":SIGKILL (Kill -9)"
    [139]=":SIGSEGV Segmentation Fault"
    [141]=":SIGPIPE (Broken Pipe)"
    [143]=":SIGTERM (Termination)"
    [255]=":General Runtime Error"
)

declare -A AWS_ERR_MAP >/dev/null 2>&1
# shellcheck disable=SC2034 # used by the commented-out code in mkpromptcmd
AWS_ERR_MAP=(
    [252]=":AWS Invalid Syntax/Parameter"
    [253]=":AWS Invalid Configuration"
    [254]=":AWS Service Error"
)

declare -A CURL_ERR_MAP >/dev/null 2>&1
# shellcheck disable=SC2034 # used by the commented-out code in mkpromptcmd
CURL_ERR_MAP=(
    [6]=":DNS Resolution Error"
    [7]=":Failed Connect"
    [28]=":Timeout"
    [35]=":SSL/TLS Error"
    [45]=":Interface Error"
    [52]=":Empty Reply"
    [56]=":Connection Reset"
)

case "$(uname -s 2>/dev/null)" in
    Linux)
        ERR_MAP[135]=":SIGBUS Bus Error"
        ERR_MAP[110]=":ETIMEDOUT Connection Timed Out"
        ERR_MAP[111]=":ECONNREFUSED Connection Refused"
        ERR_MAP[36]=":ENAMETOOLONG File Name Too Long"
        ;;
    Darwin|FreeBSD|NetBSD|OpenBSD)
        ERR_MAP[138]=":SIGBUS Bus Error"
        ERR_MAP[60]=":ETIMEDOUT Connection Timed Out"
        ERR_MAP[61]=":ECONNREFUSED Connection Refused"
        ERR_MAP[63]=":ENAMETOOLONG File Name Too Long"
        ;;
    SunOS)
        ERR_MAP[138]=":SIGBUS Bus Error"
        ERR_MAP[145]=":ETIMEDOUT Connection Timed Out"
        ERR_MAP[146]=":ECONNREFUSED Connection Refused"
        ERR_MAP[78]=":ENAMETOOLONG File Name Too Long"
        ;;
    CYGWIN*)
        ERR_MAP[138]=":SIGBUS Bus Error"
        ERR_MAP[116]=":ETIMEDOUT Connection Timed Out"
        ERR_MAP[111]=":ECONNREFUSED Connection Refused"
        ERR_MAP[91]=":ENAMETOOLONG File Name Too Long"
        ;;
    Haiku)
        unset 'ERR_MAP[133]' 'ERR_MAP[141]'
        ERR_MAP[135]=":SIGPIPE (Broken Pipe)"
        ERR_MAP[150]=":SIGTRAP Trace/Breakpoint Trap"
        ERR_MAP[158]=":SIGBUS Bus Error"
        ;;
    Minix)
        ERR_MAP[$(( 128 + $(kill -l BUS) ))]=":SIGBUS Bus Error"
        ;;
esac

true
#export PS1="\${TAB_TITLE}\n    \[\e[${pscolor}\]### \u@\H \${shicon} \${LOAD_INFO}\${AWS_INFO}\${ERROR_MSG}\[\e[${pscolor}\] ?\$? &\j \d \t ###\[\e[0m\]\n\w # "
#export PS1="\${TAB_TITLE}\n    \[\e[${pscolor}\]### \u@\h \${shicon} \${LOAD_INFO}\${AWS_INFO}\${ERROR_MSG}\[\e[${pscolor}\] ?\$? &\j \A ###\[\e[0m\]\n\w # "
#export PS1="\${TAB_TITLE}\n    \[\e[${pscolor}\]### \u@\h \${shicon} \${LOAD_INFO}\${ERROR_MSG}\[\e[${pscolor}\] ?\$? &\j \A ###\[\e[0m\]\n\w # "
#export PS1="\${TAB_TITLE}\n  ${rstcolor}${hcolor}##${pscolor} \u@\h \${shicon} \${LOAD_INFO}\${ERROR_MSG}${pscolor} ?\$? &\j \A ${rstcolor}${hcolor}##${rstcolor}\${PSGITREPO}\${PSAWS}\n\w # "
#export PS1="\${TAB_TITLE}  ${rstcolor}${pscolor}#\${PSBANNER}${rstcolor}\n  ${hcolor}##${pscolor} \u@\h \${shicon} \${LOAD_INFO}\${ERROR_MSG}${pscolor} ?\$? &\j \A ${rstcolor}${hcolor}##${rstcolor}\${PSGITREPO}\${PSAWS}\n# \w \n# "
#export PS1="\${TAB_TITLE}${rstcolor}${pscolor}\${PSBANNER}${rstcolor}\n  ${hcolor}##${pscolor} \u@\h \${shicon} \${LOAD_INFO}\${ERROR_MSG}${pscolor}?\$? &\j \A ${rstcolor}${hcolor}##${rstcolor}\${PSALERT}\${PSGITREPO}\${PSAWS}\n\w # "
#export PS1="\${TAB_TITLE}${rstcolor}${pscolor}\${PSBANNER}${rstcolor}\n  ${hcolor}##${pscolor} \u@\h \${shicon} \${LOAD_INFO}${pscolor}?\$? &\j \t \$VIRTUAL_ENV_PROMPT ${rstcolor}${hcolor}##${rstcolor}\${PSALERT}\${PSGITREPO}\${PSAWS}\${ERROR_MSG}\n\w # "
export PS1="\${TAB_TITLE}${rstcolor}${pscolor}\${PSBANNER}${rstcolor}\n  ${hcolor}##${pscolor} \u@\h \${shicon} \${LOAD_INFO}${pscolor}?\$? &\j \t \$VIRTUAL_ENV_PROMPT ${rstcolor}${hcolor}##${rstcolor}\${PSALERT}\${PSGITREPO}\${ERROR_MSG}\n\w # "

##################################################
# SSH AGENT
##################################################
if [[ -f ~/.ssh/.agent ]]
then
    . ~/.ssh/.agent >/dev/null 2>&1
    # ssh-add exits 2 only when it can't reach the agent (avoids ps -p, which minix lacks)
    ssh-add -l >/dev/null 2>&1
    if [[ $? -eq 2 ]]
    then
        rm -f ~/.ssh/.agent >/dev/null 2>&1
        ssh-agent -s > ~/.ssh/.agent 2>/dev/null
        . ~/.ssh/.agent >/dev/null 2>&1
    fi
fi

##################################################
# compiler security
##################################################
# -fharden-control-flow-redundancy (GCC 14+) intentionally left out: real
# perf cost, and silently unavailable/errors pre-14.
export myCFLAGS="-O2 -pipe -Wall -Wextra -Wformat=2 -Wtrampolines -Wbidi-chars=any -Wimplicit-fallthrough -Werror=format-security -Wconversion -Wshadow -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -ftrivial-auto-var-init=zero -fstrict-flex-arrays=3 -fzero-call-used-regs=used-gpr -fno-delete-null-pointer-checks -fno-strict-overflow -fno-strict-aliasing -fPIE -fno-plt"
export myLDFLAGS="-pie -Wl,-z,now -Wl,-z,relro -Wl,-z,noexecstack -Wl,-z,separate-code -Wl,-z,defs -Wl,--as-needed -Wl,-z,nodlopen"

if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]
then
    export myCFLAGS="${myCFLAGS/ -fcf-protection=full/}"
    export myLDFLAGS=""
fi

# minix 3.3: clang 3.4, no PIE
if [[ "$(uname -s 2>/dev/null)" == "Minix" ]]
then
    export myCFLAGS="-O2 -pipe -Wall -Wextra -Wformat=2 -Werror=format-security -Wconversion -Wshadow -fstack-protector -fno-strict-aliasing -fwrapv"
    export myLDFLAGS=""
fi

mkdir -p ~/.terraform.d/plugin-cache

##################################################
# terraform
##################################################
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
if ! grep -Eq "^plugin_cache_dir" ~/.terraformrc >/dev/null 2>&1
then
    echo "plugin_cache_dir = \"$TF_PLUGIN_CACHE_DIR\"" >> ~/.terraformrc
fi

##################################################
# python
##################################################
export PYTHONSTARTUP=~/pythonrc.py
export WORKON_HOME=~/.virtualenvs
export VIRTUAL_ENV_DISABLE_PROMPT=1

# pip mgmt
alias pipup="pip list --outdated"
alias pipug="pip list --outdated | cut -d' ' -f1 | xargs -n1 pip install -U"
alias pipr="pip freeze > requirements.txt"
alias pipi="pip install -r requirements.txt"

# python debugging
# pdb myscript.py
alias pdb="python -m pdb"
# debug in VS: debugpy --listen 5678 myscript.py
alias debugpy="python -m debugpy"


##################################################

function psg()
{
    local out
    out="$(psa |grep -Ev " $$ .*grep .*$*")"
    head -n 1 <<<"$out"
    tail -n +2 <<<"$out" | grep -Ei -- "$*"
}

##################################################
function dogitps()
{
    PSGITREPO=""
    local mypwd="$PWD"
    local mygitbranch mygitbranchcount mygitrepo
    while [[ -n "$mypwd" ]]
    do
        if [[ -d "${mypwd}/.git" ]]
        then
            if mygitrepo=$(git config remote.origin.url 2>/dev/null)
            then
                mygitbranch=$(git branch --show-current)
                mygitbranchcount=$(git branch |wc -l |awk '{print $1}')
                PSGITREPO=$(echo -e "\n\033[93;1;40m  ## GIT ${mygitbranch}/${mygitbranchcount} @ ${mygitrepo} ##\033[0m")
            else
                PSGITREPO=""
            fi
            break
        else
            mypwd="${mypwd%/*}"
        fi
    done
}

##################################################
if [[ -e ~/.gitconfig ]] \
&& command -v git >/dev/null 2>&1
then
    #ihavegit="YES"
    function cd()
    {
        builtin cd "$@" || return
        dogitps
        return 0
    }
else
    #ihavegit="NO"
    PSGITREPO=""
fi


##################################################
function getaws()
{
    if [[ ! -n "$AWS_PROFILE" ]]
    then 
        echo "FAIL: YOU NEED TO SETUP \$AWS_PROFILE"
        return 1
    fi

    local myawsrole myawsaccountname myregion
    PSAWS=""

    # shellcheck disable=SC2034 # used by the commented-out code in mkpromptcmd
    myoldawsprofile=""

    myawsrole=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null | cut -d'/' -f2 |cut -d':' -f6 2>/dev/null)

    myawsaccountname=$(aws account get-account-information 2>/dev/null | jq -r '.AccountName' 2>/dev/null)

    myregion=$(aws configure get region)
    if [[ "$myregion" != '' ]]
    then
        export AWS_DEFAULT_REGION="$myregion"
    fi
    export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

    PSAWS=$(echo -e "\n\033[93;1;40m  ## ${AWS_PROFILE}: ${myawsrole} @ ${myawsaccountname} @ ${AWS_REGION:-$AWS_DEFAULT_REGION} ##\033[0m ")
    export PSAWS

    echo "AWS  Profile: $AWS_PROFILE"
    echo "Amazon  Role: $myawsrole"
    echo "Account Name: $myawsaccountname"
    echo "Default Region: $AWS_DEFAULT_REGION"
    echo "Manual Region: $AWS_REGION"
    echo "Policy Names:"
    for i in $(aws iam list-attached-role-policies --role-name "$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null |cut -d'/' -f2)" | jq -r '.AttachedPolicies[].PolicyName' 2>/dev/null)
    do
        echo -e "\t$i\n"
    done
}

##################################################
function bail()
{
    tail "$@" |bat --paging=never -l log
}

##################################################
function sshagent()
{
    local file

    if [[ -f ~/.ssh/.agent ]]
    then
        . ~/.ssh/.agent
        ssh-add -l >/dev/null 2>&1
        if [[ $? -ne 2 ]]
        then
            echo "ssh-agent already running.  importing environment..."
        else
            rm -f ~/.ssh/.agent
            echo "starting ssh-agent"
            ssh-agent -s > ~/.ssh/.agent
            . ~/.ssh/.agent
        fi
    fi
    if ! ssh-add -l >/dev/null 2>&1
    then
        [[ -f /usr/lib/ssh-keychain.dylib ]] && ssh-add -s /usr/lib/ssh-keychain.dylib
        [[ -f /usr/lib64/pkcs11/opensc-pkcs11.so ]] && ssh-add -s /usr/lib64/pkcs11/opensc-pkcs11.so
        for file in ~/.ssh/*
        do
            grep -q PRIVATE "$file" && ssh-add "$file"
        done
    fi
    true
}


##################################################
function dnstxtwrap() {
    cat "$1" |gzip -9|base64 -w75 |sed -e 's/^/  "/' |sed -e 's/$/"/'
}

##################################################
function dnstxt2txt()
{
    if ! command -v base64 >/dev/null 2>&1
    then
        echo "FAIL: base64 not found" >&2
        return 1
    fi
    host -t TXT "$1" ${2:+"$2"} \
        |grep -v ':' \
        |sed -e 's/^[^"]*"//' \
        |tr -d '" ' \
        |base64 -d \
        |gzip -d
}

##################################################
function getarpa()
{
    echo "$1" | awk -F. '{print $4"."$3"."$2"."$1".in-addr.arpa."}'
}

##################################################
function mysleep
{
    local c=1
    local i=0
    for (( i=$1; i>=1; i-- ))
    do
        printf "\e[K#sleeping %s/%s T-%s\r" "$c" "$1" "$i"
        sleep 1
        (( c++ ))
    done
    printf "\e[K\r"
}

##################################################
whoipy() {
    if [ -z "$1" ]
    then
        echo "Usage: whoipy <IP_ADDRESS>" >&2
        return 1
    fi
    if ! python3 -c 'import ipwhois' &>/dev/null
    then
        echo "FAIL: ipwhois not found."
        echo "Install with python3 -m pip install ipwhois"
        return 1
    fi

    local clean_ip
    clean_ip=$(printf '%s' "$1" | tr -cd '0-9a-fA-F.:')

    if [ -z "$clean_ip" ]
    then
        echo "Error: No valid IP address characters provided." >&2
        return 1
    fi

    python3 -c '
import json
from ipwhois import IPWhois
from sys import argv

print(json.dumps(IPWhois(argv[1]).lookup_rdap()))
' "$clean_ip" |jq
}
# jq -r '.asn_description'
# jq -r '.network.name'
# jq -r '.objects[].contact.name'
# jq '.network.cidr |split(", ")[]'
# jq '.asn_cidr |split(", ")[]'

##################################################
function patchgem()
{
    if ! command -v gem >/dev/null 2>&1
    then
        echo "FAIL: no gem installed"
        return 1
    fi
    if brew --prefix ruby >/dev/null 2>&1 \
    && [[ -d "$(brew --prefix ruby)" ]] 
    then
        echo "chmod'ing u+w ruby dir"
        chmod -R u+w "$(brew --prefix ruby)" /opt/homebrew/Cellar/ruby
    fi

    gem update --system
    gem update
    echo "######## gem outdated report"
    gem outdated
    echo "######################################"
}

##################################################
function patchmods()
{
    mkbanner "patchpip"
    patchpip 2>&1 |tee /tmp/patchpip.log
    mkbanner "patchpipx"
    patchpipx 2>&1 |tee /tmp/patchpipx.log
    mkbanner "patchgem"
    patchgem 2>&1 |tee /tmp/patchgem.log
    mkbanner "patchcpan"
    patchcpan 2>&1 |tee /tmp/patchcpan.log
    mkbanner "patchnpm"
    patchnpm 2>&1 |tee /tmp/patchnpm.log
    mkbanner "patchcargo"
    patchcargo 2>&1 |tee /tmp/patchcargo.log
}

##################################################
# Usage: patchpip [python]   (default python3, or the active venv's)
# "python -m pip" so a non-Python "pip" earlier in PATH (pkgsrc's Perl one) isn't used
function patchpip()
{
    local py="${1:-python3}" pkg
    if ! "$py" -m pip --version >/dev/null 2>&1
    then
        echo "FAIL: no pip for $py ($(command -v "$py"))"
        return 1
    fi
    echo "Using $("$py" -m pip --version)"
    "$py" -m pip install --upgrade pip
    "$py" -m pip install pip-review
    "$py" -m pip_review --auto --continue-on-fail
    for pkg in $("$py" -m pip list --outdated | tail -n +3 | awk '{print $1}')
    do
        echo "#################### $pkg"
        "$py" -m pip install -U --force-reinstall --ignore-requires-python "$pkg"
    done
    if [[ -d ~/Library/Caches/pip ]]
    then
        echo 'Deleting ~/Library/Caches/pip'
        rm -rf ~/Library/Caches/pip >/dev/null 2>&1
    fi
    echo "######## pip list --outdated report"
    "$py" -m pip list --outdated
    echo "######################################"
}

##################################################
# Python CLI tools installed with pipx or "uv tool", each in its own venv
function patchpipx()
{
    local found=0
    if command -v pipx >/dev/null 2>&1
    then
        found=1
        pipx upgrade-all
        echo "######## pipx list --short report"
        pipx list --short
    fi
    if command -v uv >/dev/null 2>&1
    then
        found=1
        uv tool upgrade --all
        echo "######## uv tool list report"
        uv tool list
    fi
    if (( ! found ))
    then
        echo "FAIL: neither pipx nor uv found"
        return 1
    fi
    echo "######################################"
}

##################################################
function cpanhbinstall()
{
    if ! command -v brew >/dev/null 2>&1 || ! brew list perl >/dev/null 2>&1
    then
        echo "FAIL: brew perl not found"
        return 1
    fi
    rm -rf ~/.cpan/build >/dev/null 2>&1
    brew list xz >/dev/null 2>&1 || brew install -y xz
    local prefix pbin xz LIBLZMA_INCLUDE LIBLZMA_LIB CFLAGS LDFLAGS
    prefix="$(brew --prefix)"
    pbin="$(brew --prefix perl)/bin"
    xz="$(brew --prefix xz)"
    PATH="$pbin:$PATH" \
    LIBLZMA_INCLUDE="$xz/include" \
    LIBLZMA_LIB="$xz/lib" \
    CFLAGS="-I$prefix/include" \
    LDFLAGS="-L$prefix/lib" \
    "$pbin/cpan" "$@"
}

##################################################
# Upgrade all outdated CPAN modules.
#   Mac:            Homebrew perl
#   Linux, Cygwin:  system perl (/usr/bin/perl)
#   root (Cygwin: Administrators group) installs into perl's site dirs,
#   everyone else installs into ~/perl5 (local::lib layout).
function patchcpan()
{
    local os perl pbin brewprefix is_root=0
    os="$(uname -s 2>/dev/null)"

    #case "$os" in
    #    CYGWIN*|MSYS*|MINGW*) id -G | grep -qw 544 && is_root=1 ;;
    #    *)                    [[ "$(id -u)" -eq 0 ]] && is_root=1 ;;
    #esac
    [[ "$(id -u)" -eq 0 ]] && is_root=1
    case "$os" in
        Darwin)
            brewprefix="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null)}"
            perl="$brewprefix/opt/perl/bin/perl"
            if [[ -z "$brewprefix" ]] || [[ ! -x "$perl" ]]
            then
                echo "FAIL: brew perl not found (brew install perl)"
                return 1
            fi
            ;;
        *)
            perl=/usr/bin/perl
            [[ -x "$perl" ]] || perl="$(command -v perl 2>/dev/null)"
            if [[ -z "$perl" ]]
            then
                echo "FAIL: perl not found"
                return 1
            fi
            ;;
    esac
    pbin="$(dirname "$perl")"

    if [[ ! -x "$pbin/cpan" ]]
    then
        echo "FAIL: $pbin/cpan not found"
        if command -v dnf >/dev/null 2>&1
        then
            echo "      dnf install perl-CPAN"
        elif command -v apt-get >/dev/null 2>&1
        then
            echo "      apt-get install perl"
        elif [[ "$os" == CYGWIN* ]]
        then
            echo "      install the Cygwin perl package with setup"
        fi
        return 1
    fi
    if ! command -v make >/dev/null 2>&1
    then
        echo "FAIL: make not found (needed to build modules)"
        return 1
    fi

    local -x PATH="$pbin:$PATH"
    local -x PERL_MM_USE_DEFAULT=1

    local ll="$HOME/perl5"
    if [[ "$is_root" == 1 ]]
    then
        echo "Running as root: installing into $perl site dirs"
        # empty == unset to perl, and keeps the caller's values intact
        local -x PERL5LIB="" PERL_LOCAL_LIB_ROOT="" PERL_MB_OPT="" PERL_MM_OPT=""
    else
        echo "Running as $(id -un): installing into $ll"
        mkdir -p "$ll"
        PATH="$ll/bin:$PATH"
        local -x PERL5LIB="$ll/lib/perl5"
        local -x PERL_LOCAL_LIB_ROOT="$ll"
        local -x PERL_MB_OPT="--install_base \"$ll\""
        local -x PERL_MM_OPT="INSTALL_BASE=$ll"
    fi

    if [[ -n "$brewprefix" ]]
    then
        if [[ -d "$brewprefix/opt/xz" ]]
        then
            local -x LIBLZMA_INCLUDE="$brewprefix/opt/xz/include"
            local -x LIBLZMA_LIB="$brewprefix/opt/xz/lib"
        fi
        local -x CFLAGS="-I$brewprefix/include"
        local -x LDFLAGS="-L$brewprefix/lib"
    fi

    echo "Using $pbin/cpan"
    "$pbin/cpan" CPAN App::cpanoutdated

    local outdated="" dir dirs=()
    [[ "$is_root" == 1 ]] || dirs+=("$ll/bin")
    # shellcheck disable=SC2016 # $Config is perl, not shell
    dirs+=("$("$perl" -MConfig -e 'print $Config{installsitescript}')" \
           "$("$perl" -MConfig -e 'print $Config{installsitebin}')" \
           "$pbin")
    for dir in "${dirs[@]}"
    do
        if [[ -f "$dir/cpan-outdated" ]]
        then
            outdated="$dir/cpan-outdated"
            break
        fi
    done
    if [[ -z "$outdated" ]]
    then
        echo "FAIL: cpan-outdated not found after installing App::cpanoutdated"
        return 1
    fi

    "$pbin/cpan" -O
    "$pbin/cpan" -u
    for mod in $("$perl" "$outdated" -p)
    do
        echo "#################### $mod"
        "$pbin/cpan" -f -i "$mod"
    done
    for mod in $("$perl" "$outdated" --verbose | awk '{print $4}')
    do
        echo "#################### $mod"
        "$pbin/cpan" -f -i "$mod"
    done

    # new XS DLLs under /usr need a rebase on Cygwin; this runs it at the next setup
    if [[ "$os" == CYGWIN* ]] \
    && command -v rebase-trigger >/dev/null 2>&1
    then
        rebase-trigger fullrebase
    fi

    for dir in ~/.cpan/build ~/.local/share/.cpan/build
    do
        if [[ -d "$dir" ]]
        then
            echo "Deleting $dir"
            rm -rf "$dir" >/dev/null 2>&1
        fi
    done
    echo "######## cpan-outdated --verbose report"
    "$perl" "$outdated" --verbose
    echo "######################################"
}

##################################################
function patchnpm()
{
    if ! command -v npm >/dev/null 2>&1
    then
        echo "FAIL: npm not found"
        return 1
    fi
    npm install -g npm@latest
    npm outdated -g
    npm update -g
    echo "######## npm outdated -g report"
    npm outdated -g
    echo "######################################"
}

##################################################
# rustup update only refreshes the toolchains (rustc, cargo, clippy...);
# binaries from "cargo install" are updated separately
function patchcargo()
{
    local crate
    if ! command -v cargo >/dev/null 2>&1
    then
        echo "FAIL: cargo not found"
        return 1
    fi
    if command -v rustup >/dev/null 2>&1
    then
        rustup self update
        rustup update
    fi
    if command -v cargo-install-update >/dev/null 2>&1
    then
        # cargo-update also handles crates installed from git
        cargo install-update -a
    else
        # Registry crates only ("name vX.Y.Z:"); cargo install is a no-op
        # when the installed version is already the latest
        for crate in $(cargo install --list | awk '/^[^ ]+ v[^ ]+:$/ { print $1 }')
        do
            cargo install --locked "$crate" || cargo install "$crate"
        done
    fi
    echo "######## cargo install --list report"
    cargo install --list
    echo "######################################"
}

##################################################
function patchapt()
{
    if ! command -v apt >/dev/null 2>&1
    then
        echo "FAIL: apt not found"
        return 1
    fi
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade -y
    apt-get update -y
    apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade -y
    apt-get update -y
    apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" auto-remove -y
    apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" autoremove -y
    apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" clean -y
    apt-file update
    systemctl --failed
}

##################################################
function patchpkgin()
{
    if command -v pkgin >/dev/null 2>&1
    then
        sudo pkgin update
        echo y|sudo pkgin upgrade
    else
        echo "FAIL: pkgin not found"
        return 1
    fi
}

##################################################
function patchhaiku()
{
    pkgman refresh
    pkgman update -y
    pkgman full-sync
}

##################################################
function patchdnf()
{
    if ! command -v dnf >/dev/null 2>&1
    then
        echo "FAIL: dnf not found"
        return 1
    fi
    if uname -r 2>/dev/null |grep -qi amzn
    then
        dnf --refresh update -y --releasever=latest
    else
        dnf --refresh update -y
    fi
    command -v rpmconf >/dev/null 2>&1 || dnf install -y rpmconf
    rpmconf -a
    dnf needs-restarting
}

##################################################
function myunixclam()
{
    local freshclam clamscan confdir conf db log hint t
    local -a asroot=(sudo) targets paths

    case "$(uname -s 2>/dev/null)" in
        FreeBSD) hint="sudo pkg install -y clamav" ;;
        SunOS)   hint="sudo pkg install antivirus/clamav" ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1
            then
                hint="sudo apt-get install -y clamav clamav-freshclam"
            else
                hint="sudo dnf install -y clamav clamav-update"
            fi
            ;;
        *)
            echo "FAIL: myunixclam is for FreeBSD, OpenIndiana, Fedora, and Ubuntu"
            return 1
            ;;
    esac

    freshclam="$(command -v freshclam)"
    clamscan="$(command -v clamscan)"
    if [[ -z "$freshclam" || -z "$clamscan" ]]
    then
        echo "FAIL: NO CLAMAV: RUN $hint"
        return 1
    fi
    (( EUID == 0 )) && asroot=()

    # Ask ClamAV which config dir it was built with, since every OS differs
    confdir="$(clamconf 2>/dev/null | awk '/^Checking configuration files in/ {print $NF; exit}')"
    if [[ -z "$confdir" ]]
    then
        for t in /etc/clamav /etc /usr/local/etc
        do
            [[ -e "$t/freshclam.conf" ]] && { confdir="$t"; break; }
        done
    fi
    if [[ -z "$confdir" ]]
    then
        echo "FAIL: can't find the ClamAV config directory"
        return 1
    fi
    conf="$confdir/freshclam.conf"
    if [[ ! -s "$conf" ]]
    then
      # Leave paths and DatabaseOwner to this build's defaults
      "${asroot[@]}" tee "$conf" >/dev/null <<EOF
DatabaseMirror    database.clamav.net
MaxAttempts       5
CompressLocalDatabase no
EOF
    fi
    perl -pi -e 's/^Example//' "$conf"
    if grep -q '^Example' "$conf"
    then
        echo "FAIL: comment out the Example line in $conf"
        return 1
    fi

    # clamscan doesn't read freshclam.conf, so pass it the database freshclam updates
    db="$(clamconf 2>/dev/null | awk -F'"' '/^Config file:/ { f = ($0 ~ /freshclam/) } f && /^DatabaseDirectory = / { print $2; exit }')"

    # A running freshclam daemon holds the update lock and keeps the database current
    if pgrep -x freshclam >/dev/null 2>&1
    then
        echo "SKIPPING freshclam.  The freshclam daemon is already updating the database"
    else
        "${asroot[@]}" nice "$freshclam" --show-progress -v
    fi

    targets=(
        ${VIRTUAL_ENV:+"$VIRTUAL_ENV"}
        "${HOME}"/Downloads
        "${HOME}"/Documents
        "${HOME}"/.cpan
        "${HOME}"/.local
        "${HOME}"/.npm
        "${HOME}"/.vscode
        "${HOME}"/.vscode-server
        "${HOME}"/.mozilla/firefox/*/extensions
        "${HOME}"/snap/firefox/common/.mozilla/firefox/*/extensions
        "${HOME}"/.var/app/org.mozilla.firefox/.mozilla/firefox/*/extensions
    )
    for t in "${targets[@]}"
    do
        [[ -e "$t" ]] && paths+=("$t")
    done
    if (( ${#paths[@]} == 0 ))
    then
        echo "FAIL: nothing to scan"
        return 1
    fi

    log="${HOME}/.cache/clamscan.log"
    mkdir -p "${HOME}/.cache" || return 1
    # Rootless podman storage is huge and mostly unreadable by its owner
    nice "$clamscan" -r -i \
        ${db:+--database="$db"} \
        --detect-pua=no \
        --fail-if-cvd-older-than=7 \
        --exclude-dir="^$HOME/\.local/share/containers" \
        --max-filesize=500M --max-scansize=1000M --max-dir-recursion=30 \
        --log="$log" \
        "${paths[@]}"
}


##################################################
function highlight()
{
  if [ -z "$1" ]
  then
    echo "Usage: <command> | highlight <pattern> [color]" >&2
    echo -e "Colors:\n\tred\n\tgreen\n\tyellow\n\tblue\n\tpurple\n\tcyan\n\twhite\n\tbg-red\n\tbg-yellow"

    return 1
  fi
  local pattern="$1"
  local color="${2:-cyan}"
  local code
  local grepcmd

  case "$color" in
    red)     code="1;31" ;;
    green)   code="1;32" ;;
    yellow)  code="1;33" ;;
    blue)    code="1;34" ;;
    magenta|purple) code="1;35" ;;
    cyan)    code="1;36" ;;
    white)   code="1;37" ;;
    # Background colors
    bg-red)    code="41;97;1" ;;
    bg-yellow) code="43;30;1" ;;
    *)       code="$color" ;; # Fallback: allows raw ANSI like "0;35" or "48;5;208"
  esac

  if grep --help 2>&1 |grep -q color \
  && [[ "${PIPESTATUS[1]}" == 0 ]] \
  && command -v ggrep >/dev/null 2>&1
  then
     grepcmd='ggrep'
  else
     grepcmd='grep'
  fi
  GREP_COLORS="mt=$code" $grepcmd -E --color=always "$pattern|$"
}

##################################################
function shellcolors()
{
    for i in {0..255}
    do
        reg="\e[${i}m"
        bold="\e[${i};1m"
        bak="\e[$((i+10))m"
        reset="\e[0m"
        name="COLOR$i"
        printf "%-10s ${reg}%-10s${reset} ${bold}%-10s${reset} ${bak}%-10s${reset}\n" \
        "$name" "Text" "Bold" "  BG  "
    done
}

##################################################
function mybeep()
{
    echo -e "\a\a\a\a\a"
    sleep 3
    echo -e "\a\a\a\a\a"
    sleep 3
    echo -e "\a\a\a\a\a"
}

##################################################
function urldecode() 
{
    local url_encoded="${1//+/ }"
    printf '%b\n' "${url_encoded//%/\\x}"
}

##################################################
function mytfdoc()
{
    if [[ ! -d ".terraform" ]]
    then
        echo "This is not a terraform dir"
        return 1
    fi
    mkdir -p docs >/dev/null 2>&1
    terraform-docs markdown . --output-file docs/tfdoc.md
    terraform-docs json . --output-file docs/tfdoc.json
    terraform-docs tfvars hcl . --output-file docs/tfdoc.tfvars.hcl
    terraform-docs tfvars json . --output-file docs/tfdoc.tfvars.json
    terraform-docs toml . --output-file docs/tfdoc.toml
    terraform-docs xml . --output-file docs/tfdoc.xml
    terraform-docs yaml . --output-file docs/tfdoc.yaml
    terraform graph -type=plan |terraform-graph-beautifier --output docs/tfgraph.html
}

##################################################
function tferaws()
{
    local accountname
    local res

    if [[ -n "$1" ]]
       then
        accountname="$1"
    else
        echo "FAIL: must provide account name as arg 1"
        return 1
    fi

    if [[ -z "$AWS_REGION" ]]
       then
        echo "FAIL: AWS_REGION is not set"
        return 1
    fi

    if [[ -z "$AWS_PROFILE" ]]
       then
        echo "FAIL: AWS_PROFILE is not set"
        return 1
    fi

    for res in $(terraformer import aws list |grep -v identitystore)
       do
      terraformer import aws \
        --resources="${res}" \
        --regions="${AWS_REGION}" \
        --profile="${AWS_PROFILE}" \
        --path-pattern="${accountname}/${AWS_REGION}/${res}"
    done
}

##################################################
function tferazure()
{
    local accountname
    local subscription_id
    local subscription_name
    local res

    if [[ -n "$1" ]]
       then
      accountname="$1"
    else
      echo "FAIL: must provide account name as arg 1"
      return 1
    fi

    subscription_id="$(az account show --query id -o tsv)"
    subscription_name="$(az account show --query name -o tsv)"

    if [[ -z "$subscription_id" ]]
       then
      echo "FAIL: unable to determine active Azure subscription"
      return 1
    fi

    export ARM_SUBSCRIPTION_ID="$subscription_id"

    for res in $(terraformer import azure list)
       do
      terraformer import azure \
        --resources="${res}" \
        --path-pattern="${accountname}/${subscription_name}/${res}"
    done
}
##################################################
function tferk8s()
{
    local context
    local res

    context="$(kubectl config current-context)"

    if [[ -z "$context" ]]
       then
      echo "FAIL: unable to determine current Kubernetes context"
      return 1
    fi

    export KUBE_CONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
    export KUBE_CTX="$context"

    for res in $(terraformer import kubernetes list)
       do
      terraformer import kubernetes \
        --resources="${res}" \
        --path-pattern="${context}/${res}"
    done
}

##################################################
function mycheckov() 
{
    terraform init
    terraform plan --out delme.binary
    terraform show -json delme.binary | jq > delme.json
    checkov -f delme.json
}

##################################################
function failalarm()
{
  mkbanner "FAIL" 2>/dev/null
  local reg
  local bold
  local bak
  local reset
  local name
  local i
  for i in {30..37}
  do
    reg="\e[${i}m"
    bold="\e[${i};1m"
    bak="\e[$((i+10))m"
    reset="\e[0m"
    name="FAIL"
    printf "${bold}%-10s${reset} ${bak}%-10s${reset} " \
      "$name" "$name"
  done
  echo ''
  mkbanner "FAIL" 2>/dev/null
  false
}


##################################################
function mkbanner()
{
    local display="${1:-BLAH}"
    local chars="${2:-#}"
    local count
    count=$(echo "$display" |wc -c |awk '{print $1}')
    local printnum=$(( ( ${COLUMNS:-$(tput cols)} / 2 ) - ( count / 2 ) - 2 ))

    printf '%*s' $printnum ' '|tr ' ' "$chars" 
    echo -n "  $display  "
    printf '%*s' $printnum ' '|tr ' ' "$chars"
    echo ''
}

##################################################
function mysysinfo()
{
    local lbl=$'\e[96;1m' dim=$'\e[2m' rst=$'\e[0m'
    local os kernel arch cpu cores ncpu load up s secs boot b k
    local memtotal memavail dfopt ro l1 l5 l15 sys n v ext
    local reg='/proc/registry/HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/Windows NT/CurrentVersion'
    local -a info words

    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' '-'

    kernel="$(uname -sr 2>/dev/null)"
    arch="$(uname -m 2>/dev/null)"
    sys="$(uname -s 2>/dev/null)"
    case "$sys" in
        Linux|CYGWIN*)
            if [[ -d "$reg" ]]
            then
                os="$(tr -d '\0' <"$reg/ProductName" 2>/dev/null)"
                b="$(tr -d '\0' <"$reg/CurrentBuild" 2>/dev/null)"
                # Windows 11 still reports its ProductName as Windows 10
                (( ${b:-0} >= 22000 )) && os="${os/Windows 10/Windows 11}"
                os="$os $(tr -d '\0' <"$reg/DisplayVersion" 2>/dev/null) (build $b)"
            else
                os="$(awk '/^PRETTY_NAME=/ { v = substr($0, 13); gsub(/"/, "", v); print v }' /etc/os-release 2>/dev/null)"
            fi
            cpu="$(awk -F': *' '/^model name/ { print $2; exit }' /proc/cpuinfo 2>/dev/null)"
            # ARM's /proc/cpuinfo has no model name
            [[ -z "$cpu" ]] && cpu="$(lscpu 2>/dev/null | awk -F': *' '/^Model name/ { print $2; exit }')"
            read -r memtotal memavail < <(awk '
                /^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } /^MemFree:/ { f = $2 }
                END { if (!a) a = f; printf "%.0f %.0f\n", t * 1024, a * 1024 }' /proc/meminfo 2>/dev/null)
            ;;
        Darwin)
            os="$(sw_vers 2>/dev/null | awk -F':[ \t]*' '
                /ProductName/ { n = $2 } /ProductVersion/ { v = $2 } /BuildVersion/ { b = $2 }
                END { print n " " v " (" b ")" }')"
            cpu="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
            if [[ "$(sysctl -n hw.nperflevels 2>/dev/null)" == 2 ]]
            then
                cores="($(sysctl -n hw.perflevel0.logicalcpu)P+$(sysctl -n hw.perflevel1.logicalcpu)E)"
            fi
            memtotal="$(sysctl -n hw.memsize 2>/dev/null)"
            # Same "available" as the Mac free(): free + file cache + purgeable
            memavail="$(vm_stat 2>/dev/null | awk '
                NR == 1 { match($0, /page size of [0-9]+/); ps = substr($0, RSTART + 13, RLENGTH - 13); next }
                { split($0, kv, ":"); v = kv[2]; gsub(/[^0-9]/, "", v); p[kv[1]] = v }
                END { printf "%.0f\n", (p["Pages free"] + p["File-backed pages"] + p["Pages purgeable"]) * ps }')"
            ;;
        FreeBSD)
            os="$(freebsd-version 2>/dev/null)"
            os="${os:+FreeBSD $os}"
            cpu="$(sysctl -n hw.model 2>/dev/null)"
            read -r memtotal memavail < <(sysctl -n hw.physmem hw.pagesize \
                vm.stats.vm.v_free_count vm.stats.vm.v_inactive_count 2>/dev/null |
                awk '{ v[NR] = $1 } END { printf "%.0f %.0f\n", v[1], (v[3] + v[4]) * v[2] }')
            ;;
        OpenBSD|NetBSD)
            cpu="$(sysctl -n hw.model 2>/dev/null)"
            # NetBSD's 64-bit total is hw.physmem64; OpenBSD's is hw.physmem, and its
            # sysctl exits 0 on unknown names, so test the output, not the status
            memtotal="$(sysctl -n hw.physmem64 2>/dev/null)"
            [[ -n "$memtotal" ]] || memtotal="$(sysctl -n hw.physmem 2>/dev/null)"
            memavail="$(vmstat -s 2>/dev/null | awk '
                /bytes per page/ { ps = $1 } /pages free$/ { f = $1 } /pages inactive$/ { i = $1 }
                END { printf "%.0f\n", (f + i) * ps }')"
            ;;
        SunOS)
            os="$(awk '{ sub(/^[ \t]+/, ""); print; exit }' /etc/release 2>/dev/null)"
            cpu="$(psrinfo -pv 2>/dev/null | awk '{ l = $0 } END { sub(/^[ \t]+/, "", l); print l }')"
            read -r memtotal memavail < <(kstat -p unix:0:system_pages:physmem \
                unix:0:system_pages:freemem 2>/dev/null |
                awk -v ps="$(pagesize 2>/dev/null)" '
                    /physmem/ { t = $2 } /freemem/ { f = $2 }
                    END { printf "%.0f %.0f\n", t * ps, f * ps }')
            boot="$(kstat -p unix:0:system_misc:boot_time 2>/dev/null | awk '{ print $2 }')"
            ;;
    esac

    if [[ -z "$os" || "$os" == "$kernel" ]]
    then
        os="$kernel, $arch"
    else
        os="$os, $kernel, $arch"
    fi
    read -ra words <<<"${cpu:-$(uname -p 2>/dev/null)}"
    cpu="${words[*]}"
    ncpu="$(getconf _NPROCESSORS_ONLN 2>/dev/null)"
    ncpu="${ncpu:-${PSCPUCOUNT#/}}"

    if [[ -r /proc/loadavg ]]
    then
        read -r l1 l5 l15 _ </proc/loadavg
        load="$l1 $l5 $l15"
    else
        s="$(uptime 2>/dev/null)"
        load="${s##*load average*: }"
        load="${load//,/}"
    fi

    if [[ -r /proc/uptime ]]
    then
        read -r secs _ </proc/uptime
        secs="${secs%.*}"
    else
        [[ -z "$boot" ]] && boot="$(sysctl -n kern.boottime 2>/dev/null)"
        # macOS and FreeBSD print "{ sec = N, usec = N } date", OpenBSD prints N
        [[ "$boot" =~ sec\ =\ ([0-9]+) ]] && boot="${BASH_REMATCH[1]}"
        [[ "$boot" =~ ^[0-9]+$ ]] && secs=$(( ${EPOCHSECONDS:-$(date +%s)} - boot ))
    fi
    if [[ -n "$secs" ]]
    then
        up="$((secs / 86400))d $((secs % 86400 / 3600))h $((secs % 3600 / 60))m"
        up="${up#0d }"
    else
        s="$(uptime 2>/dev/null)"
        up="${s#*up }"
        up="${up%,*user*}"
        up="${up%,*load*}"
    fi

    info=(
        Host   "$HOSTNAME"
        User   "$USER (uid $UID)"
        OS     "$os"
        CPU    "$cpu, $ncpu cpus${cores:+ $cores}"
        Load   "$load (1, 5, 15 min)"
        Uptime "$up"
    )

    # Each source emits "A|iface|addr[/len]|netmask" and "R|gateway|iface";
    # temporary and deprecated IPv6 addresses are dropped at the source
    while IFS='|' read -r n v
    do
        info+=("$n" "$v")
    done < <(
        if [[ "$sys" == CYGWIN* ]]
        then
            # English ipconfig only; "Default Gateway" may continue on the next lines
            ipconfig 2>/dev/null | awk '
                { sub(/\r$/, "") }
                /^[^ \t]/ { ifc = $0; sub(/^.* adapter /, "", ifc); sub(/:$/, "", ifc); gw = 0; next }
                / : / { gw = 0; v = $0; sub(/^[^:]*: */, "", v) }
                !/ : / { v = $0 }
                { gsub(/^ +| +$/, "", v); sub(/\(.*/, "", v) }
                /IPv4 Address/ { a = v }
                /IPv6 Address/ && !/Temporary|Link-local/ { print "A|" ifc "|" v }
                /Subnet Mask/ && a != "" { print "A|" ifc "|" a "|" v; a = "" }
                /Default Gateway/ { gw = 1 }
                gw && v ~ /^[0-9]+\.[0-9.]+$/ && !r++ { print "R|" v "|" ifc }'
        elif [[ "$sys" == Linux ]] && command -v ip >/dev/null 2>&1
        then
            ip -o addr show 2>/dev/null | awk '
                / temporary| deprecated/ { next }
                {
                    ifc = $2; sub(/@.*/, "", ifc); a = $4
                    # Point-to-point: "inet 10.8.0.2 peer 10.8.0.1/32"
                    if (a !~ /\// && $5 == "peer") { p = $6; sub(/^[^\/]*/, "", p); a = a p }
                    print "A|" ifc "|" a
                }'
            ip route show default 2>/dev/null | awk 'NR == 1 {
                for (i = 1; i < NF; i++) { if ($i == "via") g = $(i + 1); if ($i == "dev") d = $(i + 1) }
                print "R|" g "|" d }'
        else
            # BSD/macOS/Solaris/net-tools ifconfig: hex, dotted or "Mask:" netmasks,
            # "prefixlen N", or the length already on the address
            ifconfig -a 2>/dev/null | awk '
                /^[^ \t]/ { ifc = $1; sub(/:$/, "", ifc) }
                $1 == "inet" || $1 == "inet6" {
                    a = $2; m = ""
                    if (a == "addr:") a = $3
                    sub(/^addr:/, "", a)
                    for (i = 3; i <= NF; i++) {
                        if ($i == "netmask") m = $(i + 1)
                        else if ($i ~ /^Mask:/) m = substr($i, 6)
                        else if ($i == "prefixlen") a = a "/" $(i + 1)
                        else if ($i == "temporary" || $i == "deprecated") next
                    }
                    sub(/%[^\/]*/, "", a)
                    print "A|" ifc "|" a "|" m
                }'
            { route -n get default 2>/dev/null || netstat -rn 2>/dev/null; } | awk '
                $1 == "gateway:" { g = $2 } $1 == "interface:" { d = $2 }
                ($1 == "default" || $1 == "0.0.0.0") && g d == "" { g = $2; d = $NF }
                END { if (g d != "") print "R|" g "|" d }'
        fi | awk -F'|' '
            function bits(m,  n, i, v, o) {
                if (m ~ /\./) {
                    split(m, o, ".")
                    for (i = 1; i <= 4; i++) for (v = o[i] + 0; v > 0; v = int(v / 2)) n += v % 2
                } else {
                    sub(/^0x/, "", m); m = tolower(m)
                    for (i = 1; i <= length(m); i++)
                        for (v = index("0123456789abcdef", substr(m, i, 1)) - 1; v > 0; v = int(v / 2)) n += v % 2
                }
                return n + 0
            }
            $1 == "R" { gw = $2; dev = $3; next }
            $1 != "A" || tolower($3) ~ /^(127\.|169\.254\.|::1(\/|$)|fe80:)/ { next }
            {
                a = $3
                if (a !~ /\// && $4 != "") a = a "/" bits($4)
                if (!($2 in addrs)) { order[++n] = $2; addrs[$2] = a }
                else if (index(", " addrs[$2] ", ", ", " a ", ") == 0) addrs[$2] = addrs[$2] ", " a
                if (length($2) > w) w = length($2)
            }
            END {
                # Default route interface first
                lbl = "Network"
                if (dev in addrs) { printf "%s|%-" w "s  %s\n", lbl, dev, addrs[dev]; lbl = "" }
                for (i = 1; i <= n; i++) {
                    if (order[i] == dev) continue
                    printf "%s|%-" w "s  %s\n", lbl, order[i], addrs[order[i]]; lbl = ""
                }
                if (gw dev == "") print "Gateway|none"
                else print "Gateway|" (gw != "" ? gw : "direct") (dev != "" ? " on " dev : "")
            }'
    )

    # Runs at every interactive login, so keep it short when offline: both
    # lookups run at once with a 1s timeout. dig +short prints ";;" errors on
    # stdout, so only keep address-shaped answers
    if command -v dig >/dev/null 2>&1
    then
        ext="$( {
            dig -4 +short +time=1 +tries=1 A myip.opendns.com @resolver1.opendns.com &
            dig -6 +short +time=1 +tries=1 AAAA myip.opendns.com @resolver1.opendns.com &
            wait
        } 2>/dev/null | awk '
            /^[0-9]+(\.[0-9]+)+$/ && v4 == "" { v4 = $0 }
            /:/ && /^[0-9A-Fa-f:]+$/ && v6 == "" { v6 = $0 }
            END { print v4 (v4 != "" && v6 != "" ? ", " : "") v6 }')"
        info+=(External "${ext:-unavailable}")
    else
        info+=(External "dig not installed")
    fi

    for (( k = 0; k < ${#info[@]}; k += 2 ))
    do
        printf '  %s%-8s%s %s\n' "$lbl" "${info[k]}" "$rst" "${info[k+1]}"
    done

    # -l keeps df off network mounts, which can hang a new shell
    if df -Plk / >/dev/null 2>&1
    then
        dfopt=-Plk
    else
        dfopt=-lk
    fi
    # Read-only mounts (disk images, ISOs) always look full, so skip them
    ro="$(mount 2>/dev/null | awk '/[(, ](ro|read-only)[,)]/ {
        sub(/^[^ ]+ on /, ""); sub(/ type [^ ]+ \(.*$/, ""); sub(/ \([^()]*\)$/, "")
        printf "%s|", $0 }')"
    printf '  %s%-22s %7s %7s %7s %5s%s\n' "$dim" "" size used avail use "$rst"
    {
        [[ "${memtotal:-0}" -gt 0 ]] \
            && echo "Memory|$memtotal|$(( memtotal - memavail ))|$memavail"
        df "$dfopt" 2>/dev/null | awk -v ro="|$ro" '
            NR == 1 { next }
            {
                dev = $1; mnt = $6
                for (i = 7; i <= NF; i++) mnt = mnt " " $i
                if (mnt != "/" && index(ro, "|" mnt "|")) next
                if (dev ~ /^[A-Za-z]:/) {
                    # Cygwin and WSL drive letters: show each drive once. Cygwin df
                    # folds C: into its root ("C:/cygwin64 ... /"), so keep "/" too
                    if (mnt != "/" && mnt !~ /^(\/cygdrive|\/mnt)?\/[A-Za-z]$/) next
                    dev = toupper(substr(dev, 1, 1))
                } else if (mnt != "/" && (dev !~ /^\/dev\// || dev ~ /^\/dev\/loop/)) next
                # macOS APFS helper volumes and Xcode simulator runtimes
                if (mnt ~ /^\/System\/Volumes\// && mnt != "/System/Volumes/Data") next
                if (mnt ~ /^\/Library\/Developer\/CoreSimulator\//) next
                if (seen[dev]++) next
                printf "%s|%.0f|%.0f|%.0f\n", mnt, $2 * 1024, $3 * 1024, $4 * 1024
            }'
        # ZFS datasets share their pool, so report pools instead
        command -v zpool >/dev/null 2>&1 \
            && zpool list -Hp -o name,size,alloc,free 2>/dev/null \
            | awk -F'\t' '{ printf "pool %s|%s|%s|%s\n", $1, $2, $3, $4 }'
    } | awk -F'|' '
        function h(b,  u, i) {
            split("B K M G T P", u, " ")
            for (i = 1; b >= 1024 && i < 6; i++) b /= 1024
            return sprintf((i > 1 && b < 10) ? "%.1f%s" : "%.0f%s", b, u[i])
        }
        function bar(p,  n, i, s) {
            n = int(p / 5 + 0.5)
            s = "\033[" (p >= 90 ? 31 : p >= 70 ? 33 : 32) "m"
            for (i = 1; i <= 20; i++) s = s (i <= n ? "#" : i == n + 1 ? "\033[2m." : ".")
            return "[" s "\033[0m]"
        }
        NF == 4 {
            name = length($1) > 22 ? "..." substr($1, length($1) - 18) : $1
            p = ($3 + $4) > 0 ? $3 * 100 / ($3 + $4) : 0
            printf "  %-22s %7s %7s %7s %4d%%  %s\n", name, h($2), h($3), h($4), p, bar(p)
        }'
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' '-'
    return 0
}

##################################################
if uname -os 2>/dev/null |grep -q Cygwin 
then
    alias pbcopy='cat > /dev/clipboard'
    alias pbpaste='cat /dev/clipboard'
    alias open='cygstart'

    ##
    function patchchoco()
    {
        choco upgrade all --ignore-dependencies -y
    }

    ##
    function cyginstall()
    {
      if ! cd /tmp/
      then
        echo "FAIL: no /tmp/"
        return 1
      fi
      if [[ ! -f /tmp/setup-x86_64.exe ]]
      then
        wget https://cygwin.com/setup-x86_64.exe
      fi
      chmod 700 /tmp/setup-x86_64.exe
      /tmp/setup-x86_64.exe -q -P "$@"
      cd - || return
    }

    ##
    function patchwinvs()
    {
        local extdir obsolete ext
        extdir="/cygdrive/c/users/$(whoami)/.vscode/extensions"
        obsolete="$extdir/.obsolete"

        if ps -W |grep -qi Code.exe >/dev/null 2>&1
        then
            echo "FAIL: must exit VS Code first"
            return 1
        fi

        # Update extensions
        /cygdrive/c/'Program Files'/'Microsoft VS Code'/bin/code \
               --update-extensions || return 1

        # Remove obsolete extensions
        if [[ -f "$obsolete" ]]
        then
            jq -r 'to_entries[] | select(.value == true) | .key' "$obsolete" |
            while IFS= read -r ext
            do
                case "$ext" in
                    ""|.|..|*/*) continue ;;
                esac
    
                if [[ -d "$extdir/$ext" && ! -L "$extdir/$ext" ]]
                then
                    echo "Removing obsolete extension: $ext"
                    rm -rf -- "${extdir:?}/${ext:?}"
                fi
            done
        fi
    }

    ##
    function mywinpatchall()
    {
        if ! id -G | grep -qw 544
        then
          echo "FAIL: run Cygwin as Administrator"
          return 1
        fi
        mkbanner "patchwinvs"
        patchwinvs 2>&1 |tee /tmp/patchwinvs.log
        mkbanner "patchcygwin"
        patchcygwin 2>&1 |tee /tmp/patchcygwin.log
        mkbanner "patchmsstore"
        patchmsstore 2>&1 |tee /tmp/patchmsstore.log
        mkbanner "patchchoco"
        patchchoco 2>&1 |tee /tmp/patchchoco.log
        mkbanner "patchmods"
        patchmods
        mkbanner "mywinclam"
        mywinclam 2>&1 |tee /tmp/mywinclam.log
        mkbanner "windiskclean"
        windiskclean 2>&1 |tee /tmp/windiskclean.log
        mkbanner "windiskdefrag"
        windiskdefrag 2>&1 |tee /tmp/windiskdefrag.log
    }

    ##
    function windiskclean()
    {
        local vc='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
        # shellcheck disable=SC2016 # $_ is powershell, not shell
        local ps="Get-ChildItem $vc"' | Where-Object PSChildName -ne DownloadsFolder | ForEach-Object { New-ItemProperty -Path $_.PSPath -Name StateFlags0001 -Value 2 -PropertyType DWord -Force | Out-Null }'
        ps+="; New-ItemProperty -Path $vc\\DownloadsFolder -Name StateFlags0001 -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null"
        ps+='; Start-Process cleanmgr.exe -ArgumentList /sagerun:1 -Wait'
        powershell.exe -NoProfile -Command \
        "Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile -Command $ps'" \
            && echo "Disk Cleanup finished"
    }

    ##
    function patchcygwin()
    {
        rm -f setup-x86_64.exe >/dev/null 2>&1
        wget https://cygwin.com/setup-x86_64.exe
        chmod 700 setup-x86_64.exe
        ./setup-x86_64.exe -q --upgrade-also
    }
    
    ##
    function patchmsstore()
    {
        if command -v winget >/dev/null 2>&1
        then
          winget upgrade --source msstore --accept-source-agreements
          winget upgrade --all --include-unknown --source msstore \
              --accept-source-agreements --accept-package-agreements \
              --disable-interactivity
        else
          echo "SKIPPING winget.  Install App Installer from the Microsoft Store"
        fi
        if id -G | grep -qw 544
        then
          powershell.exe -NoProfile -Command \
              'Get-CimInstance -Namespace root/cimv2/mdm/dmmap -ClassName MDM_EnterpriseModernAppManagement_AppManagement01 | Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null' \
              && echo "Store update scan started.  Updates install in the background"
        else
          echo "SKIPPING Store update scan.  Run Cygwin as Administrator"
        fi
    }
        
    ##
    function windiskdefrag()
    {
        if id -G | grep -qw 544
        then
          defrag.exe /C /O /U /V
        else
          powershell.exe -NoProfile -Command \
              "Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile -Command defrag.exe /C /O /U /V; pause'"
        fi
    }
    
    ##
    function wincleanit()
    {
        if ! id -G | grep -qw 544
        then
          echo "FAIL: run Cygwin as Administrator"
          return 1
        fi
        patchchoco
        patchmsstore
        windiskclean
        windiskdefrag
        if ! command -v sdelete >/dev/null 2>&1
        then
          echo "SKIPPING sdelete.  Install it with: choco install sdelete"
        elif [[ "$(powershell.exe -NoProfile -Command '(Get-PhysicalDisk | Where-Object DeviceId -eq (Get-Partition -DriveLetter C).DiskNumber).MediaType' | tr -d '\r')" == "SSD" ]]
        then
          echo "SKIPPING sdelete.  C: is an SSD"
        else
          sdelete -accepteula -z c:
        fi
    }

    ##
    function mywinclam()
    {
        if ! id -G | grep -qw 544
        then
          echo "FAIL: run Cygwin as Administrator"
          return 1
        fi
        local clamdir conf data wdata db winhome t
        local -a targets paths
        clamdir="$(printf '%s\n' /cygdrive/c/ProgramData/chocolatey/lib/clamav/tools/clamav-*.win.x64 | sort -V | tail -1)"
        if [[ ! -x "$clamdir/freshclam.exe" || ! -x "$clamdir/clamscan.exe" ]]
        then
            echo "FAIL: NO CLAMAV: RUN choco install -y clamav"
            return 1
        fi
        conf="$clamdir/freshclam.conf"
        # Database and logs live outside the versioned choco dir so upgrades keep them
        data=/cygdrive/c/ProgramData/clamav
        mkdir -p "$data/database" "$data/log" || return 1
        wdata="$(cygpath -w "$data")"
        if [[ ! -s "$conf" ]]
        then
          cat >"$conf" <<EOF
DatabaseDirectory $wdata\database
CVDCertsDirectory $(cygpath -w "$clamdir")\certs
UpdateLogFile     $wdata\log\freshclam.log
LogTime           yes
LogVerbose        yes
LogRotate         yes
DatabaseMirror    database.clamav.net
MaxAttempts       5
CompressLocalDatabase no
EOF
        fi
        # clamscan doesn't read freshclam.conf, so pass it the same database
        db="$(awk '$1 == "DatabaseDirectory" { sub(/^[ \t]*DatabaseDirectory[ \t]+/, ""); sub(/[ \t\r]+$/, ""); print }' "$conf")"

        winhome="/cygdrive/c/users/$(whoami)"
        targets=(
            ${VIRTUAL_ENV:+"$VIRTUAL_ENV"}
            "$winhome"/Downloads
            "$winhome"/Documents
            "$winhome"/.vscode
            "$winhome"/AppData/Roaming/Mozilla/Firefox/Profiles/*/extensions
            "${HOME}"/.cpan
            "${HOME}"/.local
            "${HOME}"/.npm
        )
        # clamscan.exe is a Windows program, so it needs Windows paths
        for t in "${targets[@]}"
        do
            [[ -e "$t" ]] && paths+=("$(cygpath -w "$t")")
        done
        if (( ${#paths[@]} == 0 ))
        then
            echo "FAIL: nothing to scan"
            return 1
        fi

        nice "$clamdir/freshclam.exe" --config-file="$(cygpath -w "$conf")" --show-progress -v
        nice "$clamdir/clamscan.exe" -r -i \
            ${db:+--database="$db"} \
            --detect-pua=no \
            --fail-if-cvd-older-than=7 \
            --exclude-dir='[\\/]OneDrive' \
            --max-filesize=500M --max-scansize=1000M --max-dir-recursion=30 \
            --log="$wdata\\log\\clamscan.log" \
            "${paths[@]}"
    }

    ##
    function winps() {
      tasklist.exe /FO TABLE
    }

    ##
    function smem() {
      tasklist.exe /FO TABLE /NH | sort -k5 -n -r 
    }

    ##
    function free() {
      powershell.exe -NoProfile -Command "Get-CimInstance Win32_OperatingSystem | Select-Object @{Name='TotalGB'; Expression={'{0:N2}' -f (\$_.TotalVisibleMemorySize / 1MB)}}, @{Name='FreeGB'; Expression={'{0:N2}' -f (\$_.FreePhysicalMemory / 1MB)}}"
    }

fi

##################################################
if uname -s 2>/dev/null|grep -q BSD
then
    alias free="top -d1 |grep -E '^Mem:|^Memory:'|head -1"
    alias patchfreebsd='sudo pkg update; echo -e "y\ny\n" |sudo pkg upgrade'
    alias patchopenbsd='sudo syspatch; sudo fw_update; sudo pkg_add -u'
fi

##################################################
if uname -os 2>/dev/null|grep -qiE 'sunos|illumos'
then
    alias free="top -d 2 |grep -E '^Memory:'|head -1"
    alias patchopenindiana='sudo pkg update'
fi

##################################################
if uname -s 2>/dev/null|grep -q Darwin
then

    alias micreset='tccutil reset Microphone'

    [[ -e /opt/local/bin/sudo ]] && alias s='/opt/local/bin/sudo'

    IFS=$'\n'
    for i in /Applications/*.app/Contents/MacOS
    do
        export PATH="${PATH}:${i}"
    done
    IFS=$' \t\n'
    command -v MacVim >/dev/null 2>&1 && alias gvim=MacVim

    ##
    function patchmac()
    {
        if command -v mas >/dev/null 2>&1
        then
          mas outdated
          mas upgrade
        else
          echo "FAIL: SKIPPING mas.  Install mas with homebrew"
        fi
        softwareupdate --list
        softwareupdate --install --all
    }
    
    ##
    function patchmacports()
    {
        xcode-select --install
        xcodebuild -checkFirstLaunchStatus \
            || /opt/local/bin/sudo xcodebuild -license accept \
            || sudo xcodebuild -license accept
        xcodebuild -runFirstLaunch -checkForNewerComponents
        echo y|sudo port selfupdate
        echo y|sudo port -cu upgrade outdated
        echo y|sudo port uninstall inactive
        echo y|sudo port reclaim
        echo y|sudo port clean --all -f all >/dev/null 2>&1 &
        # shellcheck disable=SC2024 # the list file should be owned by me, not root
        echo y|sudo port list installed > ~/port-list-installed 2>/dev/null &
        echo y|sudo port diagnose
        sudo chmod -R go+rX /opt/local/{Library,bin,sbin,lib,libexec,share,include}
    }
    ##
    function patchhomebrew()
    {
        xcode-select --install
        xcodebuild -checkFirstLaunchStatus \
            || /opt/local/bin/sudo xcodebuild -license accept \
            || sudo xcodebuild -license accept
        xcodebuild -runFirstLaunch -checkForNewerComponents
        chmod -R u+w "$(brew --prefix)"
        brew update
        brew upgrade -y
        brew cleanup
        brew doctor
        chmod -R u+w "$(brew --prefix)"
        if [[ -d ~/Library/Caches/Homebrew ]]
        then
            echo 'Deleting ~/Library/Caches/Homebrew'
            rm -rf ~/Library/Caches/Homebrew >/dev/null 2>&1
        fi
    }

    ##
    function patchmacvs()
    {
        local extdir="$HOME/.vscode/extensions"
        local obsolete="$extdir/.obsolete"
        local isrunning=0

        if pgrep -x "Code" >/dev/null 2>&1
        then
            isrunning=1
        fi

        # Update extensions
        /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code \
               --update-extensions || return 1

        # Gracefully quit VS Code
        osascript -e 'tell application "Visual Studio Code" to quit' || return 1

        # Wait for VS Code to exit
        while pgrep -x "Code" >/dev/null
        do
            sleep 1
        done

        # Remove obsolete extensions
        if [[ -f "$obsolete" ]]
        then
            jq -r 'to_entries[] | select(.value == true) | .key' "$obsolete" |
            while IFS= read -r ext
            do
                case "$ext" in
                    ""|.|..|*/*) continue ;;
                esac
    
                if [[ -d "$extdir/$ext" && ! -L "$extdir/$ext" ]]
                then
                    echo "Removing obsolete extension: $ext"
                    rm -rf -- "${extdir:?}/${ext:?}"
                fi
            done
        fi
    
        # Restart VS Code
        [[ "$isrunning" == 1 ]] && open -a "Visual Studio Code"
    }


    ##
    function mymacpatchall()
    {
        mkbanner "patchmacvs"
        patchmacvs 2>&1 |tee /tmp/patchmacvs.log
        mkbanner "patchmac"
        patchmac 2>&1 |tee /tmp/patchmac.log
        mkbanner "patchhomebrew"
        patchhomebrew 2>&1 |tee /tmp/patchhomebrew.log
        mkbanner "patchmacports"
        patchmacports 2>&1 |tee /tmp/patchmacports.log
        mkbanner "patchpkgin"
        patchpkgin 2>&1 |tee /tmp/patchpkgin.log
        mkbanner "patchmods"
        patchmods
        mkbanner "myhbrewclam"
        myhbrewclam 2>&1 |tee /tmp/myhbrewclam.log
    }

    ##
    function myhbrewclam()
    {
        if ! brew list clamav >/dev/null 2>&1
        then
            echo "FAIL: NO CLAMAV: RUN brew install -y clamav"
            return 1
        fi
        local prefix
        prefix="$(brew --prefix)"
        if [[ ! -s "$prefix/etc/clamav/freshclam.conf" ]]
        then
          cat >"$prefix/etc/clamav/freshclam.conf" <<EOF
DatabaseDirectory $prefix/var/lib/clamav
CVDCertsDirectory $prefix/etc/clamav/certs
UpdateLogFile     $prefix/var/log/freshclam.log
LogTime           yes
LogVerbose        yes
LogRotate         yes
DatabaseMirror    database.clamav.net
MaxAttempts       5
CompressLocalDatabase no
EOF
        fi
        nice "$prefix/bin/freshclam" --show-progress -v
        nice "$prefix/bin/clamscan" -r -i \
            --detect-pua=no \
            --fail-if-cvd-older-than=7 \
            --exclude-dir="^$HOME/Library/(CloudStorage|Mobile Documents|Caches)" \
            --max-filesize=500M --max-scansize=1000M --max-dir-recursion=30 \
            --log="$prefix/var/log/clamscan.log" \
            ${VIRTUAL_ENV:+"$VIRTUAL_ENV"} \
            "${HOME}"/Downloads \
            "${HOME}"/Documents \
            "${HOME}"/.cpan \
            "${HOME}"/.local \
            "${HOME}"/.npm \
            "${HOME}"/.vscode \
            "${HOME}"/Library/'Application Support'/Firefox/Profiles/*/extensions
    }

    ##
    function free()
    {
        local total_bytes swap
        total_bytes=$(sysctl -n hw.memsize) || return 1
        swap=$(sysctl -n vm.swapusage)
    
        vm_stat | awk -v total="$total_bytes" -v swap="$swap" '
        NR == 1 {
            # Use the page size vm_stat reports so it always matches its counts
            match($0, /page size of [0-9]+/)
            ps = substr($0, RSTART + 13, RLENGTH - 13)
            next
        }
        {
            split($0, kv, ":")
            val = kv[2]; gsub(/[^0-9]/, "", val)
            p[kv[1]] = val
        }
        END {
            gb = 1024 ^ 3
            free_b = p["Pages free"] * ps
            wired  = p["Pages wired down"] * ps
            comp   = p["Pages occupied by compressor"] * ps
            app    = (p["Anonymous pages"] - p["Pages purgeable"]) * ps
            cache  = (p["File-backed pages"] + p["Pages purgeable"]) * ps
            used   = app + wired + comp
            avail  = free_b + cache
    
            # vm.swapusage looks like: total = 2048.00M  used = 1024.00M  free = 1024.00M
            n = split(swap, s, " ")
            st = s[3] + 0; su = s[6] + 0; sf = s[9] + 0
    
            printf "%-6s %11s %11s %11s %11s %11s\n", "", "total", "used", "free", "cache", "available"
            printf "%-6s %10.2fG %10.2fG %10.2fG %10.2fG %10.2fG\n", "Mem:", \
                total/gb, used/gb, free_b/gb, cache/gb, avail/gb
            printf "%-6s %10.2fG %10.2fG %10.2fG\n", "Swap:", st/1024, su/1024, sf/1024
        }'
    }

    ##
    function smem()
    {
        for i in $(ps -axo pid | sort -n | grep -v PID)
        do
            /opt/local/bin/sudo footprint -p "$i" 2>/dev/null \
                | grep 'Footprint:' \
                | grep -v KB \
                | 'grep' -E ' [GM]B' \
                | cut -d':' -f1,3 \
                | cut -d'(' -f1
        done \
        | awk '{
            size = $(NF-1); unit = $NF
            mb = (unit == "GB") ? size * 1024 : size
            printf "%.2f\t%s\n", mb, $0
          }' \
        | sort -n \
        | cut -f2-
        return 0
    }
fi

##################################################

##################################################
[[ -e /etc/bashrc.mk.local ]] && . /etc/bashrc.mk.local
[[ -e ~/bashrc.mk.local ]] && . ~/bashrc.mk.local

##################################################
# Only in interactive terminals, so scp, rsync and "ssh host cmd" stay silent
[[ $- == *i* && -t 1 ]] && mysysinfo

##################################################
true
