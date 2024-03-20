#!/usr/bin/env bash

## GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-adobe-fonts.sh
## Purpose: Install Adobe Sans, Pro, and Serif fonts system-wide
## Created: 03.19.24
## Script version: 1.3

set -eo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Check if the script is run as root
if [[ "$EUID" == 0 ]]; then
    fail "You must run this script without root or sudo."
fi

# Set the variables
script_ver=1.3
pro_url="https://github.com/adobe-fonts/source-code-pro/archive/refs/tags/2.042R-u/1.062R-i/1.026R-vf.tar.gz"
sans_url="https://github.com/adobe-fonts/source-sans/archive/refs/tags/3.052.tar.gz"
serif_url="https://github.com/adobe-fonts/source-serif/archive/refs/tags/4.005.tar.gz"
cwd="$HOME/adobe-fonts-installer"
pro_dir="$cwd/pro-source"
sans_dir="$cwd/sans-source"
serif_dir="$cwd/serif-source"
install_dirs=("/usr/local/share/fonts/adobe-pro" "/usr/local/share/fonts/adobe-sans" "/usr/local/share/fonts/adobe-serif")

# Display the script banner to box and output script banner
box_out_banner_header() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner_header "Adobe Fonts Installer Script Version $script_ver"
echo

# Function to setup directories
setup_directories() {
    log "Setting up directories..."
    echo
    # Remove files from previous runs and create font output directories
    for dir in "${install_dirs[@]}"; do
        sudo rm -fr "$dir"
        sudo mkdir -p "$dir"
    done
    mkdir -p "$pro_dir" "$sans_dir" "$serif_dir"
}

# Function to download and extract fonts
download_and_extract() {
    local url="$1"
    local dir="$2"
    local tarball="$dir.tar.gz"

    echo
    log "Downloading $tarball from $url"
    wget -t 2 -cqO "$tarball" "$url" || fail "Failed to download $tarball"

    log "Extracting $tarball..."
    tar -zxf "$tarball" -C "$dir" --strip-components 1 || fail "Failed to extract $tarball"
}

# Function to move font files
move_fonts() {
    local source_dir="$1"
    local install_dir="$2"
    
    log "Moving fonts from $source_dir to $install_dir..."
    find "$source_dir" -type f \( -name "*.ttf" -o -name "*.otf" -o -name "*.woff" \) -exec sudo mv -f {} "$install_dir" \;
}

# Main function to orchestrate the script flow
main() {
    setup_directories
    download_and_extract "$pro_url" "$pro_dir"
    download_and_extract "$sans_url" "$sans_dir"
    download_and_extract "$serif_url" "$serif_dir"
    echo
    move_fonts "$pro_dir" "${install_dirs[0]}"
    move_fonts "$sans_dir" "${install_dirs[1]}"
    move_fonts "$serif_dir" "${install_dirs[2]}"
    echo
    log "Updating font cache..."
    sudo fc-cache -f
    echo
    log "Cleaning up..."
    rm -fr "$cwd" || warn "Failed to remove the leftover files."
    echo
    log 'Make sure to star the repository to show your support!'
    log "https://github.com/slyfox1186/script-repo"
}

main
