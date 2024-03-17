#!/usr/bin/env bash

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log Functions
log() { echo -e "${GREEN}[LOG]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# Check for root privileges
if [[ "$EUID" -ne 0 ]]; then
    fail "This script must be run as root. Use sudo."
fi

# Reboot prompt function
prompt_reboot() {
    echo -e "Do you want to reboot now to apply changes? [y/N]"
    read -r choice
    if [[ "$choice" == [Yy]* ]]; then
        log "Rebooting..."
        reboot
    else
        log "Manual reboot required to complete the installation."
    fi
}

# Check and install apt pkgs
check_and_install_pkgs() {
    local pkgs=(
                autoconf autoconf-archive autogen
                build-essential libtool mailutils
                m4 perl ssh python3-cmarkgfm liblz4-dev
                python3-commonmark libxxhash-dev
            )

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -l | grep -qw "$pkg"; then
            local missing_pkgs+="$pkg "
        fi
    done

    if [[ -n "$missing_pkgs" ]]; then
        apt-get install $missing_pkgs
    fi
}

# Install rsync from source
install_rsync_from_source() {
    local rsync_url="https://github.com/WayneD/rsync/archive/refs/tags/v3.2.7.tar.gz"
    local rsync_dir="rsync-3.2.7"

    log "Downloading rsync from GitHub..."
    wget -cqO rsync.tar.gz "$rsync_url" || fail "Failed to download rsync."

    log "Extracting rsync..."
    tar -zxf rsync.tar.gz || fail "Failed to extract rsync."

    cd "$rsync_dir" || fail "Failed to change directory to $rsync_dir."

    log "Configuring rsync..."
    ./configure || fail "Failed to configure rsync."

    log "Compiling rsync with parallel jobs..."
    make "-j$(nproc --all)" || fail "Failed to compile rsync."

    log "Installing rsync..."
    make install || fail "Failed to install rsync."
}

# log2ram configuration function
configure_log2ram() {
    local config_file="/etc/log2ram.conf"
    [[ -f "$config_file" ]] || fail "log2ram configuration file not found."

    log "Configuring log2ram..."
    sed -i 's/SIZE=40M/SIZE=1024M/g; s/LOG_DISK_SIZE=256M/LOG_DISK_SIZE=2048M/g' "$config_file" || warn "Failed to update log2ram configuration."

    log "Configuration updated: SIZE=512M, LOG_DISK_SIZE=1024M"
}

# Main installation function
install_log2ram() {
    log "Starting log2ram installation..."
    apt-get update && apt-get upgrade -y || fail "Failed to update/upgrade system packages."
    check_and_install_pkgs

    # Download and install log2ram
    log "Downloading log2ram from GitHub..."
    wget -cqO log2ram.tar.gz https://github.com/azlux/log2ram/archive/master.tar.gz || fail "Failed to download log2ram."

    log "Extracting log2ram..."
    mkdir log2ram
    tar -zxf log2ram.tar.gz -C log2ram --strip-components 1 || fail "Failed to extract log2ram."

    log "Running log2ram installation script..."
    (cd log2ram && ./install.sh) || fail "Failed to run log2ram installation script."

    install_rsync_from_source

    # Configure log2ram
    configure_log2ram

    log "log2ram and rsync installations completed."
    prompt_reboot
}

# Execute the installation process
install_log2ram
