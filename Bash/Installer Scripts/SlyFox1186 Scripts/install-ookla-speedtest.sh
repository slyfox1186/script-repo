#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/install-ookla-speedtest.sh
# Purpose: install Ookla speedtest program for Linux architecture x86_64
# Updated: 06.01.24
# Script version: 1.0

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set the variables
script_ver=1.0
prog_name="ookla-speedtest"
version=$(curl -fsSL "https://www.speedtest.net/apps/cli/" | grep -oP 'ookla-speedtest-\K\d+\.\d+\.\d+' | head -n1)

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

exit_function() {
    echo
    log "The script has completed"
    log "${GREEN}Make sure to ${YELLOW}star ${GREEN}this repository to show your support!${NC}"
    log "${CYAN}https://github.com/slyfox1186/script-repo${NC}"
    exit 0
}

cleanup() {
    sudo rm -fr "$archive_name" "$tar_file"
}

download_archive() {
    wget --show-progress -cqO "$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    tar -zxf "$tar_file" -C "$archive_name" || fail "Failed to extract: $tar_file"
}

install_binary_file() {
    cd "$archive_name" || fail "Failed to cd into $archive_name. Line: $LINENO"
    sudo cp -f speedtest /usr/local/bin/
    sudo chmod 755 /usr/local/bin/speedtest
    sudo chown root:root /usr/local/bin/speedtest
    cd ../
}

archive_name="$prog_name-$version"
archive_url="https://install.speedtest.net/app/cli/$prog_name-$version-linux-x86_64.tgz"
archive_ext="${archive_url//*.}"
tar_file="$archive_name.$archive_ext"

# Create output directory
[[ -d "$archive_name" ]] && sudo rm -fr "$archive_name"
mkdir -p "$archive_name"

download_archive
extract_archive
install_binary_file
cleanup
exit_function
