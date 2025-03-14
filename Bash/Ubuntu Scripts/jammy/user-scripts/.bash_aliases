#!/bin/bash
# Master .bash_aliases file - Part of the Jammy modular bash configuration
# https://github.com/slyfox1186/script-repo/tree/main/Bash/Ubuntu%20Scripts/jammy
# This file sources modular alias scripts for better organization

# Export color settings for GCC
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Setup dircolors
if [ -x '/usr/bin/dircolors' ]; then
    test -r "$HOME/.dircolors" && eval "$(dircolors -b "$HOME"/.dircolors)" || eval "$(dircolors -b)"
fi

# Check if aliases directory exists, create if not
BASH_ALIASES_DIR="$HOME/.bash_aliases.d"
[[ ! -d "$BASH_ALIASES_DIR" ]] && mkdir -p "$BASH_ALIASES_DIR"

# Source all alias modules
for module in "$BASH_ALIASES_DIR"/*.sh; do
    if [[ -f "$module" ]]; then
        source "$module"
    fi
done