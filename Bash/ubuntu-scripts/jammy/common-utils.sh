#!/usr/bin/env bash

# Common utility functions for Ubuntu Jammy scripts
# GitHub: https://github.com/slyfox1186/script-repo

# Check if the script is run as root (when root access is NOT wanted)
check_root() {
    if [[ "$EUID" -eq 0 ]]; then
        echo "You must run this script WITHOUT root/sudo."
        exit 1
    fi
}

# Check if the script requires root (when root access IS required)
require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "You must run this script with root or sudo."
        exit 1
    fi
}

# Check if a package is installed
installed() { 
    return $(dpkg-query -W -f '${Status}\n' "${1}" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}')
}

# Determine the best apt command to use
get_apt_cmd() {
    if which 'apt-fast' &>/dev/null; then
        echo 'apt-fast'
    elif which 'aptitude' &>/dev/null; then
        echo 'aptitude'
    else
        echo 'apt'
    fi
}

# Install a package if it's missing using the best available apt command
install_pkg() {
    local pkg="$1"
    if ! installed "$pkg"; then
        sudo $(get_apt_cmd) -y install "$pkg"
        return $?
    fi
    return 0
}

# Open a file in the best available editor
open_editor() {
    local file="$1"
    if command -v gedit &>/dev/null; then
        sudo gedit "$file"
    elif command -v nano &>/dev/null; then
        sudo nano "$file"
    elif command -v vim &>/dev/null; then
        sudo vim "$file"
    elif command -v vi &>/dev/null; then
        sudo vi "$file"
    else
        printf "\n%s\n" "Unable to open the file because no text editor was found."
    fi
}

# Create a backup of a file if it doesn't exist
backup_file() {
    local file="$1"
    if [[ ! -f "${file}.bak" ]]; then
        cp -f "$file" "${file}.bak"
    fi
}

# Show exit message
exit_fn() {
    printf "\n%s\n\n%s\n\n" \
        '[i] Make sure to star this repository to show your support!' \
        '[i] https://github.com/slyfox1186/script-repo/'
    exit 0
}

# Error handling function
fail() {
    echo -e "\\n[ERROR] $1\\n"
    read -p "Press enter to exit."
    exit 1
}