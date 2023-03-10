# "${HOME}/.bashrc": executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL='ignoreboth'

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE='20000'
HISTFILESIZE='20000'

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x '/usr/bin/lesspipe' ] && eval "$(SHELL='/bin/sh' lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r '/etc/debian_chroot' ]; then
    debian_chroot=$(cat '/etc/debian_chroot')
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt='yes';;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt='yes'

if [ -n "$force_color_prompt" ]; then
    if [ -x '/usr/bin/tput' ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt='yes'
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# if this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# alias definitions
if [ -f "${HOME}/.bash_aliases" ]; then
    source "${HOME}/.bash_aliases"
fi

# enable programmable completion features
if ! shopt -oq posix; then
  if [ -f '/usr/share/bash-completion/bash_completion' ]; then
    source '/usr/share/bash-completion/bash_completion'
  elif [ -f '/etc/bash_completion' ]; then
    source '/etc/bash_completion'
  fi
fi

##############################################################################################################

# function definitions
if [ -f "${HOME}/.bash_functions" ]; then
    source "${HOME}/.bash_functions"
fi

# custom user vars
PATH=\
/usr/local/sbin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin:\
/usr/local/cuda-12.1/bin:\
/snap/bin:\
"${HOME}"/.local/bin
export PATH

PS1='\[\e[0;1;93;48;5;16m\]\w\n\[\e[0;1;38;5;46;48;5;16m\]\T\n\[\e[0;1;38;5;198;48;5;16m\]\u\[\e[0;1;97;48;5;16m\]@\[\e[0;1;96;48;5;16m\]\h\[\e[0;1;93;48;5;16m\]$\[\e[0m\]'
export PS1

TMP="${HOME}/tmp"
export TMP

LAN="$(hostname -I)"
export LAN

WAN="$(curl -sS 'https://checkip.amazonaws.com')"
export WAN

THREADS="$(nproc --all)"
export THREADS

CPUS="$((THREADS/2))"
export CPUS
