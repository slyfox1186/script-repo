# $HOME/.bashrc: executed by bash(1) for non-login shells.
# See /usr/share/doc/bash/examples/startup-files (in the package bash-doc) for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return ;;
esac

# Don't put duplicate lines or lines starting with a space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# For setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=10000
HISTFILESIZE=20000

# make less more friendly for non-text input files, see lesspipe(1)
[[ -x '/usr/bin/lesspipe' ]] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [[ -z "$debian_chroot:-" ]] && [[ -r /etc/debian_chroot ]]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt="yes" ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [[ -n "$force_color_prompt" ]]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt="yes"
    else
	color_prompt=""
    fi
fi

if [[ "$color_prompt" = "yes" ]]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [[ -x /usr/bin/dircolors ]]; then
    if test -r "$HOME/.dircolors"; then
	eval $(dircolors -b "$HOME/.dircolors")
    else
        eval $(dircolors -b)
    fi
    alias ls="ls --color=always --group-directories-first"
    alias grep="grep --color=always"
fi

# colored GCC warnings and errors
GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Alias definitions.
# You may want to put all your additions into a separate file like
# $HOME/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [[ -f "$HOME/.bash_aliases" ]]; then
    source "$HOME/.bash_aliases"
fi

####################
## CUSTOM SECTION ##
####################

if [[ -f $HOME/.bash_functions ]]; then
    source $HOME/.bash_functions
fi

if [[ -f $HOME/.cargo/env ]]; then
    source $HOME/.cargo/env
fi

threads=$(nproc --all)
cpus=$((threads / 2))
lan=$(ip route get 1.2.3.4 | awk '{print $7}')
wan=$(curl --connect-timeout 1 -fsS "https://checkip.amazonaws.com")
PS1='\n\[\e[38;5;227m\]\w\n\[\e[38;5;215m\]\u\[\e[38;5;183;1m\]@\[\e[0;38;5;117m\]\h\[\e[97;1m\]\\$\[\e[0m\]'
PYTHONUTF8=1
MAGICK_THREAD_LIMIT=16
export cpus lan PS1 PYTHONUTF8 threads wan MAGICK_THREAD_LIMIT

# SET THE SCRIPT'S PATH VARIABLE
PATH="\
/usr/lib/ccache/bin:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/opt/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin:\
/snap/bin\
"
export PATH

if [[ -f /usr/lib/wsl/lib/libcuda.so.1.1 ]] && [[ ! -L /usr/lib/wsl/lib/libcuda.so.1 ]]; then
    sudo ln -sf /usr/lib/wsl/lib/libcuda.so.1.1 /usr/lib/wsl/lib/libcuda.so.1
fi
