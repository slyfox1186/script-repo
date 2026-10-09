#!/bin/bash
# Directory colors and file display settings

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
# LESSPIPE SETUP
# ====================
# Make less more friendly for non-text input files
[[ -x "/usr/bin/lesspipe" ]] && eval "$(SHELL=/bin/sh lesspipe)"

# Terminal colors - improve readability in less and man pages
export LESS_TERMCAP_mb=$'\E[1;31m'     # begin blink
export LESS_TERMCAP_md=$'\E[1;36m'     # begin bold
export LESS_TERMCAP_me=$'\E[0m'        # reset bold/blink
export LESS_TERMCAP_so=$'\E[01;33m'    # begin reverse video
export LESS_TERMCAP_se=$'\E[0m'        # reset reverse video
export LESS_TERMCAP_us=$'\E[1;32m'     # begin underline
export LESS_TERMCAP_ue=$'\E[0m'        # reset underline

# Less options
export LESS="-R -F -X"  # Enable color, exit if file fits on screen, don't clear screen