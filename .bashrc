# 20261007 Kirby


##################################################
# SETUP PATH
##################################################
export HOME=${HOME:-~}
export oldPATH=$PATH
unset PATH
#export PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/libexec:/usr/local/bin:/usr/local/sbin:$HOME/.local/bin:$HOME/bin

for i in \
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
    /usr/local/sbin \
    $HOME/.local/bin \
    $HOME/bin \
    $HOME/scripts
do
    [[ -d "$i" ]] && export PATH="${PATH:+${PATH}:}${i}"
done

IFS=: read -ra dirs <<< "$oldPATH"
for i in "${dirs[@]}"; do
    if [[ ":$PATH:" != *":$i:"* ]]; then
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
    for i in $(cat /etc/ld.so.conf /etc/ld.so.conf.d/* 2>/dev/null |grep -E '^/')
    do
        newldpath="${newldpath}:${i}"
    done
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

if command -v bat >/dev/null 2>&1
then
    if command -v less >/dev/null 2>&1
    then
        export BAT_PAGER="less -RFX"
    fi
    if bat --list-themes 2>&1 |grep -q Catpuccin
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
export VISUAL=vi
export EDITOR=vi

if [[ -d /opt/homebrew ]]
then
    eval "$(/opt/homebrew/bin/brew shellenv bash |grep -v 'export PATH=')"
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
alias cp="cp -v"
alias mv="mv -v"
alias rm="rm -v"
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

if ps -e -o pid= >/dev/null 2>&1
then
    alias p='ps -eww -o uid,user,tty,pid,ppid,pcpu,pmem,nice,stime,command'
    alias psa='ps -eww -o user,pid,ppid,pgid,stat,tty,nice,pcpu,pmem,stime,command'
    if ps -e -o lxc= >/dev/null 2>&1
    then
        alias myps='ps -eww -o lxc,user,pid,ppid,nice,pcpu,pmem,command'
    else
        alias myps='ps -eww -o user,pid,ppid,nice,pcpu,pmem,command'
    fi
else
    alias p='ps -ef'
    alias psa='ps -ef'
    alias myps='ps -ef'
fi
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
if [[ "$USER" == "root" ]] \
|| [[ "$USER" == "Administrator" ]] 
then
    umask 022
else
    umask 077
fi

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
    local last_cmd
    local load
    last_cmd=$(history 1)

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

    if [[ "$ihavegit" == "YES" ]] \
    && echo "$last_cmd" |grep -qE 'git |GIT'
    then
        dogitps
    fi

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


if [[ -e ~/.gitconfig ]] \
&& command -v git >/dev/null 2>&1
then
    ihavegit="YES"
else
    PSGITREPO=""
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
[[ $HOSTNAME =~ [rv][123456789].mk.lan ]] && shicon="🔩"

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
AWS_ERR_MAP=(
    [252]=":AWS Invalid Syntax/Parameter"
    [253]=":AWS Invalid Configuration"
    [254]=":AWS Service Error"
)

declare -A CURL_ERR_MAP >/dev/null 2>&1
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

[[ -e ~/myvenv/bin/activate ]] && . ~/myvenv/bin/activate


##################################################
function dogitps()
{
    PSGITREPO=""
    local mypwd="$PWD"
    while [[ -n "$mypwd" ]]
    do
        if [[ -d "${mypwd}/.git" ]]
        then
            if mygitrepo=$(git config remote.origin.url 2>/dev/null)
            then
                local mygitbranch=$(git branch --show-current)
                local mygitbranchcount=$(git branch |wc -l |awk '{print $1}')
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
function cd()
{
    builtin cd "$@" && {
        dogitps
    }
}
##################################################
function getaws()
{
    if [[ ! -n "$AWS_PROFILE" ]]
    then 
        echo "FAIL: YOU NEED TO SETUP \$AWS_PROFILE"
        return 1
    fi

   myoldawsprofile=""

    myawsrole=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null | cut -d'/' -f2 |cut -d':' -f6 2>/dev/null)

    myawsaccountname=$(aws account get-account-information 2>/dev/null | jq -r '.AccountName' 2>/dev/null)

    myregion=$(aws configure get region)
    if [[ "$myregion" != '' ]]
    then
        export AWS_DEFAULT_REGION="$myregion"
    fi
    export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

    export PSAWS=$(echo -e "\n\033[93;1;40m  ## ${AWS_PROFILE}: ${myawsrole} @ ${myawsaccountname} @ ${AWS_REGION:-$AWS_DEFAULT_REGION} ##\033[0m ")

    echo "AWS  Profile: $AWS_PROFILE"
    echo "Amazon  Role: $myawsrole"
    echo "Account Name: $myawsaccountname"
    echo "Default Region: $AWS_DEFAULT_REGION"
    echo "Manual Region: $AWS_REGION"
    echo "Policy Names:"
    for i in $(aws iam list-attached-role-policies --role-name $(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null |cut -d'/' -f2) | jq -r '.AttachedPolicies[].PolicyName' 2>/dev/null)
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
    cat $1 |gzip -9|base64 -w75 |sed -e 's/^/  "/' |sed -e 's/$/"/'
}

##################################################
function dnstxt2txt()
{
    host -t TXT $1 $2 |grep -v ':' |sed -e 's/^[^"]*"//' |tr -d '" ' |base64 -d |gzip -d
}

##################################################
function getarpa()
{
    echo $1 | awk -F. '{print $4"."$3"."$2"."$1".in-addr.arpa."}'
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
        let c++
    done
    printf "\e[K\r"
}

##################################################
whoipy() {
    if [ -z "$1" ]; then
        echo "Usage: whoipy <IP_ADDRESS>" >&2
        return 1
    fi
    if ! python3 -c 'import ipwhois' &>/dev/null; then
        echo "ipwhois not found. Installing via pip..." >&2
        python3 -m pip install ipwhois || return 1
    fi

    local clean_ip
    clean_ip=$(printf '%s' "$1" | tr -cd '0-9a-fA-F.:')

    if [ -z "$clean_ip" ]; then
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
function patchpip()
{
    pip install --upgrade pip
    pip install pip-review
    pip-review --auto --continue-on-fail
    for pkg in $(pip list --outdated | tail -n +3 | awk '{print $1}')
    do 
        echo "#################### $pkg"
        pip install -U --force-reinstall --ignore-requires-python $pkg
    done
    if [[ -d ~/Library/Caches/pip ]]
    then
        echo 'Deleting ~/Library/Caches/pip'
        rm -rf ~/Library/Caches/pip >/dev/null 2>&1
    fi
}

##################################################
function patchcpan()
{
    if ! command -v cpan >/dev/null 2>&1
    then
        echo "FAIL: cpan not found"
        return 1
    fi
    export PERL_MM_USE_DEFAULT=1
    cpan -O
    cpan -u
    if [[ -d ~/.cpan/build ]]
    then
        echo 'Deleting ~/.cpan/build'
        rm -rf ~/.cpan/build >/dev/null 2>&1
    fi
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
}

##################################################
function patchapt()
{
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
alias patchfreebsd='sudo pkg update; echo y|sudo pkg upgrade'
alias patchopenbsd='sudo syspatch; sudo fw_update; sudo pkg_add -u'
alias patchpkgin='sudo pkgin update; echo y|sudo pkgin upgrade'
alias patchopenindiana='sudo pkg update'
alias patchhaiku='pkgman refresh; pkgman update -y; pkgman full-sync'
alias patchminix='pkgin update; pkgin -y full-upgrade'

##################################################
function patchdnf()
{
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
function patchcygwin()
{
    rm -f setup-x86_64.exe >/dev/null 2>&1
    wget --no-check-certificate https://cygwin.com/setup-x86_64.exe
    chmod 700 setup-x86_64.exe
    ./setup-x86_64.exe -q --upgrade-also
}

##################################################
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

##################################################
function windiskclean()
{
    local vc='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    local ps="Get-ChildItem $vc"' | Where-Object PSChildName -ne DownloadsFolder | ForEach-Object { New-ItemProperty -Path $_.PSPath -Name StateFlags0001 -Value 2 -PropertyType DWord -Force | Out-Null }'
    ps+="; New-ItemProperty -Path $vc\\DownloadsFolder -Name StateFlags0001 -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null"
    ps+='; Start-Process cleanmgr.exe -ArgumentList /sagerun:1 -Wait'
    powershell.exe -NoProfile -Command \
        "Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile -Command $ps'" \
        && echo "Disk Cleanup finished"
}

##################################################
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

##################################################
function wincleanit()
{
    windiskclean
    windiskdefrag
    sdelete -z c:
}
##################################################
function patchmac()
{
    if command -v mas >/dev/null 2>&1
    then
      mas outdated
      mas upgrade
    else
      echo "SKIPPING mas.  Install mas with homebrew"
    fi
    softwareupdate --list
    softwareupdate --install -all
}

##################################################
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
    echo y|sudo port list installed > ~/port-list-installed 2>/dev/null &
    echo y|sudo port diagnose
    sudo chmod -R 755 /opt/local/Library
    sudo chmod -R 755 /opt/local/bin
    sudo chmod -R 755 /opt/local/sbin
    sudo chmod -R 755 /opt/local/lib
    sudo chmod -R 755 /opt/local/libexec
    sudo chmod -R 755 /opt/local/share
    sudo chmod -R 755 /opt/local/include
    sudo chmod 4511 /opt/local/bin/sudo
}
##################################################
function patchhomebrew()
{
    xcode-select --install
    xcodebuild -checkFirstLaunchStatus \
        || /opt/local/bin/sudo xcodebuild -license accept \
        || sudo xcodebuild -license accept
    xcodebuild -runFirstLaunch -checkForNewerComponents
    brew update
    brew upgrade -y
    brew cleanup
    brew doctor
    if [[ -d ~/Library/Caches/Homebrew ]]
    then
        echo 'Deleting ~/Library/Caches/Homebrew'
        rm -rf ~/Library/Caches/Homebrew >/dev/null 2>&1
    fi
}

##################################################
function highlight()
{
  if [ -z "$1" ]; then
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
  if uname -s 2>/dev/null|grep -qEi 'Darwin|BSD' \
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
    for i in {0..255}; do
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

    for res in $(terraformer import aws list)
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
    local count=$(echo $display |wc -c |awk '{print $1}')
    local printnum=$(( ( ${COLUMNS:-$(tput cols)} / 2 ) - ( $count / 2 ) - 2 ))

    printf '%*s' $printnum ' '|tr ' ' "$chars" 
    echo -n "  $display  "
    printf '%*s' $printnum ' '|tr ' ' "$chars" 
    echo ''
}

##################################################
if uname -o 2>/dev/null |grep -q Cygwin 
then
    alias pbcopy='cat > /dev/clipboard'
    alias pbpaste='cat /dev/clipboard'
    alias open='cygstart'

    function cyginstall()
    {
      if ! cd /tmp/
      then
        echo "FAIL: no /tmp/"
        return 1
      fi
      if [[ ! -f /tmp/setup-x86_64.exe ]]
      then
        wget --no-check-certificate https://cygwin.com/setup-x86_64.exe
      fi
      chmod 700 /tmp/setup-x86_64.exe
      /tmp/setup-x86_64.exe -q -P "$@"
      cd -
    }

    function winps() {
      tasklist.exe /FO TABLE
    }
    function smem() {
      tasklist.exe /FO TABLE /NH | sort -k5 -n -r 
    }

    function free() {
      powershell.exe -NoProfile -Command "Get-CimInstance Win32_OperatingSystem | Select-Object @{Name='TotalGB'; Expression={'{0:N2}' -f (\$_.TotalVisibleMemorySize / 1MB)}}, @{Name='FreeGB'; Expression={'{0:N2}' -f (\$_.FreePhysicalMemory / 1MB)}}"
    }

fi

##################################################
if uname -s 2>/dev/null|grep -q BSD
then
    alias free="top -d1 |grep -E '^Mem:'"
fi

##################################################
if uname -os 2>/dev/null|grep -qiE 'sunos|illumos'
then
    unalias cp
    unalias rm
    unalias mv
    alias free="top -d 2 |grep -E '^Memory:'|head -1"
fi

##################################################
if uname -s 2>/dev/null|grep -q Darwin
then

    alias micreset='tccutil reset Microphone'
    alias code=Code

    [[ -e /opt/local/bin/sudo ]] && alias s='/opt/local/bin/sudo'

    IFS=$'\n'
    for i in /Applications/*.app/Contents/MacOS
    do
        export PATH="${PATH}:${i}"
    done
    IFS=$' \t\n'
	command -v MacVim >/dev/null 2>&1 && alias gvim=MacVim

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

##
    function smem()
    {
        for i in $(ps -axo pid | sort -n | grep -v PID)
        do
            /opt/local/bin/sudo footprint -p $i 2>/dev/null \
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
##

fi

##################################################

##################################################
[[ -e /etc/bashrc.mk.local ]] && . /etc/bashrc.mk.local
[[ -e ~/bashrc.mk.local ]] && . ~/bashrc.mk.local

##################################################
true
