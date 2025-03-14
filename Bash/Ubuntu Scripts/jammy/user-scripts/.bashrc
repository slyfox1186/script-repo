#!/usr/bin/env bash

# ===============================================================
# Enhanced .bashrc for Ubuntu - Modular Version
# Author: slyfox1186 (https://github.com/slyfox1186/script-repo)
# Source: https://github.com/slyfox1186/script-repo/tree/main/Bash/Ubuntu%20Scripts/jammy
# ===============================================================

# If not running interactively, don't do anything
case "$-" in
    *i*) ;;
    *) return ;;
esac

# Check if bashrc directory exists, create if not
BASHRC_DIR="$HOME/.bashrc.d"
[[ ! -d "$BASHRC_DIR" ]] && mkdir -p "$BASHRC_DIR"

# System info variables (used in modules and welcome message)
threads=$(nproc --all 2>/dev/null || echo "unknown")
cpus=$((threads / 2))
lan=$(ip route get 1.2.3.4 2>/dev/null | awk '{print $7}' || echo "unknown")
wan=$(curl --connect-timeout 1 -fsS "https://checkip.amazonaws.com" 2>/dev/null || echo "unknown")

# Export common variables for modules to use
export threads cpus lan wan

# Source all bashrc modules
for module in "$BASHRC_DIR"/*.sh; do
    if [[ -f "$module" ]]; then
        source "$module"
    fi
done

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