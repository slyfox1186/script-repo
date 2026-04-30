#!/usr/bin/env bash

set -euo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[LOG]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

if [[ "$EUID" -eq 0 ]]; then
    fail "This script must be run without root or sudo."
fi

prompt_reboot() {
    read -rp "Do you want to reboot now to apply changes? [y/N] " choice
    if [[ "$choice" == [Yy]* ]]; then
        log "Rebooting..."
        sudo reboot
    else
        log "Manual reboot required to complete the installation."
    fi
}

check_and_install_pkgs() {
    local pkgs=(
        autoconf autoconf-archive autogen
        build-essential libtool mailutils
        m4 perl ssh python3-cmarkgfm liblz4-dev
        python3-commonmark libxxhash-dev libzstd-dev
    )

    local missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        log "Installing ${#missing_pkgs[@]} missing package(s)..."
        sudo apt -y install "${missing_pkgs[@]}"
    fi
}

install_rsync_from_source() {
    local rsync_url="https://github.com/RsyncProject/rsync/archive/refs/tags/v3.3.0.tar.gz"
    local rsync_dir="rsync-3.3.0"

    log "Downloading rsync from GitHub..."
    wget --show-progress -cqO rsync.tar.gz "$rsync_url" || fail "Failed to download rsync."

    log "Extracting rsync..."
    tar -zxf rsync.tar.gz || fail "Failed to extract rsync."

    cd "$rsync_dir" || fail "Failed to change directory to $rsync_dir."

    log "Configuring rsync..."
    ./configure || fail "Failed to configure rsync."

    log "Compiling rsync with parallel jobs..."
    make "-j$(nproc --all)" || fail "Failed to compile rsync."

    log "Installing rsync..."
    sudo make install || fail "Failed to install rsync."
}

configure_log2ram() {
    local config_file="/etc/log2ram.conf"
    [[ -f "$config_file" ]] || fail "log2ram configuration file not found."

    log "Configuring log2ram..."
    sudo sed -i 's/SIZE=40M/SIZE=1024M/g; s/LOG_DISK_SIZE=256M/LOG_DISK_SIZE=2048M/g' "$config_file" || warn "Failed to update log2ram configuration."

    log "Configuration updated: SIZE=1024M, LOG_DISK_SIZE=2048M"
}

install_log2ram() {
    log "Starting log2ram installation..."
    sudo apt update && sudo apt -y full-upgrade || fail "Failed to update/upgrade system packages."
    check_and_install_pkgs

    log "Downloading log2ram from GitHub..."
    wget --show-progress -cqO "log2ram.tar.gz" "https://github.com/azlux/log2ram/archive/master.tar.gz" || fail "Failed to download log2ram."

    log "Extracting log2ram..."
    mkdir -p log2ram
    tar -zxf log2ram.tar.gz -C log2ram --strip-components 1 || fail "Failed to extract log2ram."

    log "Running log2ram installation script..."
    cd log2ram || fail "Failed to cd into log2ram directory."
    sudo bash install.sh || fail "Failed to run log2ram installation script."

    install_rsync_from_source

    configure_log2ram

    log "log2ram and rsync installations completed."
    prompt_reboot
}

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

cd "$build_dir" || exit 1

install_log2ram
