#!/usr/bin/env bash

# ===============================================================
# Enhanced .bashrc for Ubuntu Jammy
# Author: slyfox1186 (https://github.com/slyfox1186/script-repo)
# ===============================================================

# If not running interactively, don't do anything
case "$-" in
    *i*) ;;
    *) return ;;
esac

# ====================
# HISTORY SETTINGS
# ====================
HISTCONTROL="ignoreboth:erasedups"  # Don't save duplicate commands or commands starting with space
HISTSIZE=100000                      # Increased history size in memory
HISTFILESIZE=200000                  # Increased history file size
HISTTIMEFORMAT="%F %T "             # Add timestamp to history
HISTIGNORE="ls:ll:cd:cd -:pwd:exit:date:* --help:clear:c:cls:history"  # Commands to not record in history

# Append to history instead of overwriting
shopt -s histappend
# Record each line of multiline commands
shopt -s cmdhist 
# Save multi-line commands as one command
shopt -s lithist

# ====================
# SHELL OPTIONS
# ====================
# Check window size and update LINES/COLUMNS
shopt -s checkwinsize
# Enable ** pattern in pathname expansion
shopt -s globstar
# Include dotfiles in pattern matching
shopt -s dotglob
# Enable extended pattern matching
shopt -s extglob
# Make tab-completion case-insensitive
bind "set completion-ignore-case on"
# List all matches when multiple completions possible
bind "set show-all-if-ambiguous on"
# Match hidden files without needing the leading dot
bind "set match-hidden-files on"
# Show tab completion options on first tab press
bind "set show-all-if-ambiguous on"

# ====================
# LESSPIPE SETUP
# ====================
# Make less more friendly for non-text input files
[[ -x "/usr/bin/lesspipe" ]] && eval "$(SHELL=/bin/sh lesspipe)"

# ====================
# CHROOT DETECTION
# ====================
if [[ -z "${debian_chroot:-}" ]] && [[ -r "/etc/debian_chroot" ]]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# ====================
# PROMPT SETTINGS
# ====================
# Check for color support
case "$TERM" in
    xterm-color|*-256color) color_prompt="yes" ;;
esac

# Force colored prompt if terminal supports it
force_color_prompt="yes"
if [[ -n "$force_color_prompt" ]]; then
    if [[ -x /usr/bin/tput ]] && tput setaf 1 >&/dev/null; then
        color_prompt="yes"
    else
        color_prompt=""
    fi
fi

# Use a modern, informative prompt with git branch support
__git_ps1() {
    local b="$(git symbolic-ref HEAD 2>/dev/null)";
    if [ -n "$b" ]; then
        printf " (%s)" "${b##refs/heads/}";
    fi
}

# Define a fancy multi-line prompt
if [[ "$color_prompt" == "yes" ]]; then
    PS1='\n\[\e[38;5;227m\]\w\[\e[38;5;82m\]$(__git_ps1 " (%s)")\n\[\e[38;5;215m\]\u\[\e[38;5;183;1m\]@\[\e[0;38;5;117m\]\h\[\e[97;1m\]\\$\[\e[0m\] '
else
    PS1='\n\w$(__git_ps1 " (%s)")\n\u@\h\$ '
fi
unset color_prompt force_color_prompt

# Set xterm window title
case "$TERM" in
    xterm*|rxvt*)
        PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
        ;;
esac

# ====================
# DIRCOLORS SETUP
# ====================
# Set up colors for ls command
if [[ -x "/usr/bin/dircolors" ]]; then
    if [[ -r "$HOME/.dircolors" ]]; then
        eval "$(dircolors -b "$HOME/.dircolors")"
    else
        eval "$(dircolors -b)"
    fi
fi

# ====================
# EXTERNAL FILES
# ====================
# Load aliases
if [[ -f "$HOME/.bash_aliases" ]]; then
    source "$HOME/.bash_aliases"
fi

# Load functions
if [[ -f "$HOME/.bash_functions" ]]; then
    source "$HOME/.bash_functions"
fi

# Enable bash completion
if ! shopt -oq posix; then
    if [[ -f "/usr/share/bash-completion/bash_completion" ]]; then
        source "/usr/share/bash-completion/bash_completion"
    elif [[ -f "/etc/bash_completion" ]]; then
        source "/etc/bash_completion"
    fi
fi

# ====================
# ADDITIONAL DEPENDENCIES
# ====================
# Load cargo environment if available
if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

# ====================
# ENVIRONMENT VARIABLES
# ====================
# System info variables
threads=$(nproc --all 2>/dev/null || echo "unknown")
cpus=$((threads / 2))
lan=$(ip route get 1.2.3.4 2>/dev/null | awk '{print $7}' || echo "unknown")
wan=$(curl --connect-timeout 1 -fsS "https://checkip.amazonaws.com" 2>/dev/null || echo "unknown")

# Default applications
export EDITOR="nano"
export VISUAL="nano"
export PAGER="less"

# Performance and behavior settings
export PYTHONUTF8=1
export MAGICK_THREAD_LIMIT=16
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export LESS="-R -F -X"  # Enable color, exit if file fits on screen, don't clear screen

# Terminal colors - improve readability in less and man pages
export LESS_TERMCAP_mb=$'\E[1;31m'     # begin blink
export LESS_TERMCAP_md=$'\E[1;36m'     # begin bold
export LESS_TERMCAP_me=$'\E[0m'        # reset bold/blink
export LESS_TERMCAP_so=$'\E[01;33m'    # begin reverse video
export LESS_TERMCAP_se=$'\E[0m'        # reset reverse video
export LESS_TERMCAP_us=$'\E[1;32m'     # begin underline
export LESS_TERMCAP_ue=$'\E[0m'        # reset underline

# Export common variables
export cpus lan PS1 threads wan

# ====================
# PATH CONFIGURATION
# ====================
# Set the PATH variable with commonly used directories
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
/snap/bin"

# Add Windows paths if running in WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
    PATH="$PATH:\
/c/Windows/System32:\
/c/Program Files:\
/c/Program Files (x86)"
fi

export PATH

# ====================
# WSL SPECIFIC FIXES
# ====================
# Fix CUDA library symlinks in WSL
if [[ -f /usr/lib/wsl/lib/libcuda.so.1.1 ]] && [[ ! -L /usr/lib/wsl/lib/libcuda.so.1 ]]; then
    sudo ln -sf /usr/lib/wsl/lib/libcuda.so.1.1 /usr/lib/wsl/lib/libcuda.so.1
fi

# ====================
# PERFORMANCE TWEAKS
# ====================
# Disable flow control (Ctrl+S/Ctrl+Q) to prevent terminal freezing
stty -ixon

# ====================
# WELCOME MESSAGE
# ====================
# Display a welcome message with system information
if [[ -n "$PS1" ]]; then
    echo "Welcome, $(whoami)! Terminal ready at $(date '+%H:%M:%S')"
    echo "System: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2- | tr -d '"')"
    echo "Kernel: $(uname -sr)"
    echo "CPU cores: $threads (Physical: $cpus)"
    echo -e "IP: $lan (LAN), $wan (WAN)\n"
fi
