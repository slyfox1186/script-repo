#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'

<<<<<<< Updated upstream
log() { echo -e "$GREEN[LOG]$NC $1"; }
warn() { echo -e "$YELLOW[WARN]$NC $1"; }
fail() { echo -e "$RED[FAIL]$NC $1"; exit 1; }

if [[ "$EUID" -ne 0 ]]; then
    fail "This script must be run as root. Use sudo."
=======
if [ "$EUID" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script WITH root/sudo'
    exit 1
>>>>>>> Stashed changes
fi

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

configure_log2ram() {
    local config_file="/etc/log2ram.conf"
    [[ -f "$config_file" ]] || fail "log2ram configuration file not found."

<<<<<<< Updated upstream
    log "Configuring log2ram..."
    sed -i 's/SIZE=40M/SIZE=1024M/g; s/LOG_DISK_SIZE=256M/LOG_DISK_SIZE=2048M/g' "$config_file" || warn "Failed to update log2ram configuration."

    log "Configuration updated: SIZE=512M, LOG_DISK_SIZE=1024M"
}
=======
if [ -f "$cfile" ]; then
    sed -i 's/SIZE=40M/SIZE=512M/g' "$cfile"
    sed -i 's/LOG_DISK_SIZE=256M/LOG_DISK_SIZE=1024M/g' "$cfile"
fi

if which gedit &>/dev/null; then
    gedit "$cfile"
elif which nano &>/dev/null; then
    nano "$cfile"
elif which vim &>/dev/null; then
    vim "$cfile"
elif which vi &>/dev/null; then
    vi "$cfile"
fi
>>>>>>> Stashed changes

install_log2ram() {
    log "Starting log2ram installation..."
    apt-get update && apt-get upgrade -y || fail "Failed to update/upgrade system packages."
    check_and_install_pkgs

<<<<<<< Updated upstream
    log "Downloading log2ram from GitHub..."
    wget -cqO log2ram.tar.gz https://github.com/azlux/log2ram/archive/master.tar.gz || fail "Failed to download log2ram."

    log "Extracting log2ram..."
    mkdir log2ram
    tar -zxf log2ram.tar.gz -C log2ram --strip-components 1 || fail "Failed to extract log2ram."

    log "Running log2ram installation script..."
    (cd log2ram && ./install.sh) || fail "Failed to run log2ram installation script."

    install_rsync_from_source

    configure_log2ram

    log "log2ram and rsync installations completed."
    prompt_reboot
}

install_log2ram
=======
case "$choice" in
    1)      sudo reboot;;
    2)      exit 0;;
    *)
            clear
            printf "%s\n\n" 'Bad user input.'
            exit 1
            ;;
esac
>>>>>>> Stashed changes
