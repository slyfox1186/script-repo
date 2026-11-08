# shellcheck shell=bash

case $- in
    *i*) ;;
      *) return;;
esac

HISTCONTROL=ignoreboth

shopt -s histappend

HISTSIZE=10000
HISTFILESIZE=20000

shopt -s checkwinsize

shopt -s globstar

[ -x '/usr/bin/lesspipe' ] && eval "$(SHELL=/bin/sh lesspipe)"

if [ -z "${debian_chroot:-}" ] && [ -r '/etc/debian_chroot' ]; then
    debian_chroot=$(cat '/etc/debian_chroot')
fi

case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	color_prompt=yes
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

case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

if [ -x '/usr/bin/dircolors' ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=always --group-directories-first'
    alias grep='grep --color=always'
fi

GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'


if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

if ! shopt -oq posix; then
  if [ -f '/usr/share/bash-completion/bash_completion' ]; then
    . '/usr/share/bash-completion/bash_completion'
  elif [ -f '/etc/bash_completion' ]; then
    . '/etc/bash_completion'
  fi
fi


if [ -f ~/.bash_functions ]; then
    . ~/.bash_functions
fi

if [ -f ~/.cargo/env ]; then
    . ~/.cargo/env
fi

threads="$(nproc --all)"
cpus="$((threads / 2))"
lan="$(ip route get 1.2.3.4 | awk '{print $7}')"
wan="$(curl -s 'https://checkip.amazonaws.com')"
PYTHONUTF8=1
SHELL='/usr/bin/env bash'
export cpus lan PYTHONUTF8 SHELL threads wan

# Prompt: "(env) path [exit code]" on line 1, "user@host $ " on line 2.
# __prompt_command draws the env name, so conda's own prefix is kept off.
CONDA_CHANGEPS1=false
export CONDA_CHANGEPS1

__prompt_command() {
    # Must stay the first statement: any command before it, even "local", resets $?.
    local exit_code=$?
    local reset='\[\e[0m\]'
    local red='\[\e[0;31m\]'
    local green='\[\e[0;32m\]'
    local yellow='\[\e[0;33m\]'
    local blue='\[\e[0;34m\]'
    local cyan='\[\e[0;36m\]'

    # The env name goes through this global rather than being pasted into PS1, so a name
    # containing "$(cmd)" is shown as text instead of being run.
    __prompt_venv=""
    if [[ -n "${CONDA_DEFAULT_ENV-}" ]]; then
        __prompt_venv="(${CONDA_DEFAULT_ENV}) "
    elif [[ -n "${VIRTUAL_ENV-}" ]]; then
        __prompt_venv="(${VIRTUAL_ENV##*/}) "
    fi

    local exit_info=""
    if (( exit_code != 0 )); then
        exit_info=" ${red}[${exit_code}]${reset}"
    fi

    PS1="${yellow}"'${__prompt_venv}'"${blue}\w${reset}${exit_info}\n${green}\u${reset}@${cyan}\h${reset} \$ "
}

PROMPT_COMMAND=__prompt_command


PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/bin:\
/usr/local/cuda/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin:\
/usr/local/games:\
/usr/games:\
/snap/bin\
"
export PATH
