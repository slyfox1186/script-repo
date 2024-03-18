#!/usr/bin/env bash

# Script: build-all-gnu-safer-archlinux.sh
# Purpose: Loops multiple build scripts to optimize efficiency. This is the safer of the two scripts.
# Version: 2.0
# Updated: 01.16.2024 09:05:15 PM
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-all-gnu-safer-archlinux.sh

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to display help menu
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help    Display this help message"
    echo "  -v, --version Display script version"
    echo "  -d, --debug   Enable debug mode"
    echo "  -s, --silent  Run script silently"
    echo
}

# Function to log messages
log() {
    local message="$1"
    echo -e "${GREEN}[LOG] $(date +'%Y-%m-%d %H:%M:%S') - $message${NC}"
}

# Function to log warnings
warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN] $(date +'%Y-%m-%d %H:%M:%S') - $message${NC}"
}

# Function to log errors and exit
fail() {
    local message="$1"
    echo -e "${RED}[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $message${NC}"
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            display_help
            exit 0
            ;;
        -v|--version)
            echo "Script version: 2.0"
            exit 0
            ;;
        -d|--debug)
            set -x
            ;;
        -s|--silent)
            exec &>/dev/null
            ;;
        *)
            warn "Unknown option: $1"
            display_help
            exit 1
            ;;
    esac
    shift
done

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    fail "You must run this script WITHOUT root/sudo."
fi

cwd="$PWD/build-all-gnu-safer-arch-script"

[[ -d "$cwd" ]] && rm -fr "$cwd"
mkdir -p "$cwd/completed" "$cwd/failed"
cd "$cwd" || fail "Failed to change directory to $cwd"

log "Build All GNU Safer ArchLinux Script - version 2.0"
log "============================================================"

pkgs=(
    asciidoc autogen autoconf autoconf-archive automake binutils bison base-devel bzip2
    ccache cmake curl glibc perl-libintl-perl libtool lzip m4 meson nasm ninja texinfo
    xmlto xz yasm zlib
)

missing_pkgs=()
for pkg in "${pkgs[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        missing_pkgs+=("$pkg")
    fi
done

if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
    log "Installing missing packages: ${missing_pkgs[*]}"
    sudo pacman -Sq --needed --noconfirm "${missing_pkgs[@]}"
fi

scripts=(
    pkg-config m4 autoconf autoconf-archive
    libtool bash make sed tar gawk grep nano
    wget
)

for script in "${scripts[@]}"; do
    log "Downloading build script: $script"
    if ! wget --show-progress -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-${script}"; then
        fail "Failed to download build script: $script"
    fi
done

log "Renaming build scripts"
for file in build-*; do
    mv "$file" "$(echo "$file" | sed 's/^build-//')"
done

clear

for file in *; do
    log "Running build script: $file"
    if bash "$file"; then
        log "Build script completed successfully: $file"
        mv "$file" "completed"
    else
        warn "Build script failed: $file"
        mv "$file" "failed"
    fi
done

log "Cleaning up leftover files"
rm -fr "$cwd"

log "Make sure to star this repository to show your support!"
log "https://github.com/slyfox1186/script-repo"
exit 0
