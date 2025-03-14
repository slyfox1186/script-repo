#!/bin/bash
# Master .bash_functions file - Part of the Jammy modular bash configuration
# https://github.com/slyfox1186/script-repo/tree/main/Bash/Ubuntu%20Scripts/jammy
# This file sources modular function scripts for better organization

# EXPORT ANSI COLORS
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
export BLUE CYAN GREEN RED YELLOW NC

# Check if script directory exists, create if not
BASH_FUNCTIONS_DIR="$HOME/.bash_functions.d"
[[ ! -d "$BASH_FUNCTIONS_DIR" ]] && mkdir -p "$BASH_FUNCTIONS_DIR"

# Create common utility functions used by multiple scripts
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}

# Source all function modules
for module in "$BASH_FUNCTIONS_DIR"/*.sh; do
    if [[ -f "$module" ]]; then
        source "$module"
    fi
done