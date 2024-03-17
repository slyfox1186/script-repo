
case $- in
    *i*) ;;
      *) return ;;
esac

HISTCONTROL=ignoreboth

shopt -s histappend

HISTSIZE=10000
HISTFILESIZE=20000

shopt -s checkwinsize

shopt -s globstar

[[ -x "/usr/bin/lesspipe" ]] && eval $(SHELL=/bin/sh lesspipe)

<<<<<<< Updated upstream
if [[ -z "${debian_chroot:-}" ]] && [[ -r "/etc/debian_chroot" ]]; then
=======
if [ -z "$debian_chroot:-" ] && [ -r '/etc/debian_chroot' ]; then
>>>>>>> Stashed changes
    debian_chroot=$(cat '/etc/debian_chroot')
fi

case "$TERM" in
<<<<<<< Updated upstream
    xterm-color|*-256color) color_prompt=yes ;;
=======
    xterm-color|*-256color) color_prompt=yes;;
>>>>>>> Stashed changes
esac

force_color_prompt=yes

<<<<<<< Updated upstream
if [[ -n "$force_color_prompt" ]]; then
    if [[ -x /usr/bin/tput ]] && tput setaf 1 >&/dev/null; then
    color_prompt=yes
=======
if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	color_prompt=yes
>>>>>>> Stashed changes
    else
    color_prompt=""
    fi
fi

<<<<<<< Updated upstream
if [[ "$color_prompt" = yes ]]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
=======
if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
>>>>>>> Stashed changes
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

case "$TERM" in
<<<<<<< Updated upstream
    xterm*|rxvt*)
        PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1" ;;
    *)  ;;
=======
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
>>>>>>> Stashed changes
esac

if [[ -x "/usr/bin/dircolors" ]]; then
    test -r "$HOME/.dircolors" && eval $(dircolors -b "$HOME/.dircolors") || eval $(dircolors -b)
    alias ls="ls --color=always --group-directories-first"
    alias grep="grep --color=always"
fi

GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'


if [[ -f "$HOME/.bash_aliases" ]]; then
    . "$HOME/.bash_aliases"
fi

if ! shopt -oq posix; then
  if [ -f "/usr/share/bash-completion/bash_completion" ]; then
    . "/usr/share/bash-completion/bash_completion"
  elif [ -f "/etc/bash_completion" ]; then
    . "/etc/bash_completion"
  fi
fi


if [[ -f "$HOME/.bash_functions" ]]; then
    . "$HOME/.bash_functions"
fi

if [[ -f "$HOME/.cargo/env" ]]; then
    . "$HOME/.cargo/env"
fi

threads=$(nproc --all)
cpus=$((threads / 2))
lan=$(ip route get 1.2.3.4 | awk '{print $7}')
wan=$(curl -s 'https://checkip.amazonaws.com')
PS1='\n\[\e[38;5;227m\]\w\n\[\e[38;5;215m\]\u\[\e[38;5;183;1m\]@\[\e[0;38;5;117m\]\h\[\e[97;1m\]\\$\[\e[0m\]'
PYTHONUTF8=1
SHELL="/usr/bin/env bash"
export cpus lan PS1 PYTHONUTF8 SHELL threads wan

PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin:\
/usr/local/games:\
/usr/games:\
/snap/bin:\
/c/Windows/System32:\
/c/Program Files:\
/c/Program Files (x86):\
/c/Users/jholl/Downloads\
"
export PATH

if [ ! -f "/usr/lib/wsl/lib/libcuda.so.1.1" ] && [ -f "/usr/lib/wsl/lib/libcuda.so.1" ]; then
    sudo ln -sf /usr/lib/wsl/lib/libcuda.so.1 /usr/lib/wsl/lib/libcuda.so.1.1
fi

PATH="$PATH:$GOROOT/bin"
