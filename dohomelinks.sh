#!/usr/bin/env bash
# Clone or update scripts.and.dotfiles in ~, then symlink the managed dotfiles.
# New machine: curl -fsSL https://raw.githubusercontent.com/mtkirby/scripts.and.dotfiles/main/dohomelinks.sh | bash
# Without curl (OpenBSD):
#   git clone https://github.com/mtkirby/scripts.and.dotfiles ~/scripts.and.dotfiles && bash ~/scripts.and.dotfiles/dohomelinks.sh
# Files already in ~ are moved to <name>.bak.<timestamp>, not deleted.

repourl="https://github.com/mtkirby/scripts.and.dotfiles"
repodir="$HOME/scripts.and.dotfiles"
stamp="$(date +%Y%m%d%H%M%S)"
rc=0

cd "$HOME" || exit 1

if [[ ! -d "$repodir/.git" ]]
then
    git clone "$repourl" "$repodir" || { echo "FAIL: could not clone $repourl"; exit 1; }
elif ! git -C "$repodir" pull --ff-only
then
    # Keep going: the links still point at the copy that's there
    echo "WARN: git pull failed in $repodir; local changes:"
    git -C "$repodir" status --short
    rc=1
fi

# link <target> <name in ~>
link()
{
    # Already linked; -ef instead of readlink, which not every OS has
    [[ -L "$HOME/$2" && "$HOME/$2" -ef "$1" ]] && return 0
    if [[ -e "$HOME/$2" || -L "$HOME/$2" ]]
    then
        mv "$HOME/$2" "$HOME/$2.bak.$stamp" || return 1
        echo "Moved ~/$2 to ~/$2.bak.$stamp"
    fi
    ln -s "$1" "$HOME/$2" && echo "Linked ~/$2 -> $1"
}

for file in \
    .bashrc \
    .psqlrc \
    .screenrc \
    .vimrc \
    pythonrc.py
do
    if [[ ! -e "$repodir/$file" ]]
    then
        echo "SKIP: $file is not in $repodir"
        continue
    fi
    link "$repodir/$file" "$file" || rc=1
done

# Login shells (every macOS Terminal) read only .bash_profile
link .bashrc .bash_profile || rc=1

exit "$rc"
