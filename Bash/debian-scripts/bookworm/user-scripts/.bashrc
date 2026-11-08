# shellcheck shell=bash
# $HOME/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc) for examples

# If not running interactively, don't do anything
case "$-" in
    *i*) ;;
      *) return ;;
esac

# Don't put duplicate lines or lines starting with space in the history.
HISTCONTROL="ignoreboth"

# Append to the history file, don't overwrite it
shopt -s histappend

# For setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=10000
HISTFILESIZE=20000

# Check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar

# Make less more friendly for non-text input files, see lesspipe(1)
[[ -x "/usr/bin/lesspipe" ]] && eval $(SHELL=/bin/sh lesspipe)

# Set variable identifying the chroot you work in (used in the prompt below)
if [[ -z "${debian_chroot:-}" ]] && [[ -r "/etc/debian_chroot" ]]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# Set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt="yes" ;;
esac

# Uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt="yes"

if [[ -n "$force_color_prompt" ]]; then
    if [[ -x /usr/bin/tput ]] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48 (ISO/IEC-6429)
        # Lack of such support is extremely rare, and such a case would tend to support setf rather than setaf.
        color_prompt="yes"
    else
        color_prompt=""
    fi
fi

if [[ "$color_prompt" == "yes" ]]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
    xterm*|rxvt*) PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1" ;;
               *) ;;
esac

# Enable color support of ls and also add handy aliases
if [[ -x "/usr/bin/dircolors" ]]; then
    if test -r "$HOME/.dircolors"; then
        eval $(dircolors -b "$HOME/.dircolors")
    else
        eval $(dircolors -b)
    fi
    alias ls="ls --color=always --group-directories-first"
    alias grep="grep --color=always"
fi

# Colored GCC warnings and errors
GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Alias definitions.
# You may want to put all your additions into a separate file like
# $HOME/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [[ -f "$HOME/.bash_aliases" ]]; then
    source "$HOME/.bash_aliases"
fi

# You don't need to enable this, if it's already enabled in
# /etc/bash.bashrc and /etc/profile sources /etc/bash.bashrc
if ! shopt -oq posix; then
  if [ -f "/usr/share/bash-completion/bash_completion" ]; then
    source "/usr/share/bash-completion/bash_completion"
  elif [ -f "/etc/bash_completion" ]; then
    source "/etc/bash_completion"
  fi
fi

####################
## CUSTOM SECTION ##
####################

if [[ -f "$HOME/.bash_functions" ]]; then
    source "$HOME/.bash_functions"
fi

if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

threads=$(nproc --all)
cpus=$((threads / 2))
lan=$(ip route get 1.2.3.4 | awk '{print $7}')
wan=$(curl --connect-timeout 1 -fsS "https://checkip.amazonaws.com")
PYTHONUTF8=1
MAGICK_THREAD_LIMIT=16
export cpus lan PYTHONUTF8 threads wan MAGICK_THREAD_LIMIT

# Prompt: "(env) path [exit code]" on line 1, "user@host $ " on line 2.
# __prompt_command draws the env name, so conda's own prefix is kept off.
CONDA_CHANGEPS1=false
export CONDA_CHANGEPS1

__prompt_command() {
    # Must stay the first statement: any command before it, even "local", resets $?.
    local exit_code=$?
    local reset='\[\e[0m\]'
    local red='\[\e[0;31m\]'
    # 24-bit RGB values, so the terminal theme's palette cannot change these colors.
    local env_gray='\[\e[38;2;167;167;167m\]'
    local path_yellow='\[\e[38;2;255;255;95m\]'
    local user_orange='\[\e[38;2;255;175;95m\]'
    local at_lilac='\[\e[38;2;215;175;255m\]'
    local host_blue='\[\e[38;2;135;215;255m\]'
    local dollar_white='\[\e[38;2;255;255;255m\]'

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

    PS1="${env_gray}"'${__prompt_venv}'"${path_yellow}\w${reset}${exit_info}\n${user_orange}\u${at_lilac}@${host_blue}\h${reset} ${dollar_white}\$${reset} "
}

PROMPT_COMMAND=__prompt_command

# Set the script's path variable
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

# Fix annoying error message in WSL Linux
if [[ -f /usr/lib/wsl/lib/libcuda.so.1.1 ]] && [[ ! -L /usr/lib/wsl/lib/libcuda.so.1 ]]; then
    sudo ln -sf /usr/lib/wsl/lib/libcuda.so.1.1 /usr/lib/wsl/lib/libcuda.so.1
fi
