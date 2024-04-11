#!/usr/bin/env bash

# GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-gettext-libiconv
# Purpose: build gnu gettext + libiconv
# Updated: 08.31.23
# Script version: 2.0

set -e

# Define color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

script_ver="2.0"
archive_dir1="libiconv-1.17"
archive_dir2="gettext-0.22.5"
archive_url1="https://ftp.gnu.org/gnu/libiconv/$archive_dir1.tar.gz"
archive_url2="https://ftp.gnu.org/gnu/gettext/$archive_dir2.tar.lz"
cwd="$PWD/gettext-libiconv-build-script"
install_dir1="/usr/local/libiconv-1.17"
install_dir2="/usr/local/gettext-0.22.5"
CC="ccache gcc"
CXX="ccache g++"
CFLAGS="-O2 -march=native -mtune=native -D_FORTIFY_SOURCE=2"
CXXFLAGS="$CFLAGS"
export CC CXX CFLAGS CXXFLAGS

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%dT%H:%M:%S%z')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%dT%H:%M:%S%z')] Warning:${NC} $*"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%dT%H:%M:%S%z')] Error:${NC} $*" >&2
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Helper function to download and extract archives
download_and_extract() {
    local archive_dir=$1
    local archive_url=$2
    local archive_ext="${archive_url##*.}"

    mkdir -p "$cwd/$archive_dir" || error "Failed to create directory $cwd/$archive_dir"
    log "Downloading $archive_url..."

    if ! curl -LSso "$cwd/$archive_dir.$archive_ext" "$archive_url"; then
        error "Failed to download $archive_url"
    fi

    log "Extracting $archive_dir.$archive_ext..."

    if ! tar -xf "$cwd/$archive_dir.$archive_ext" -C "$cwd/$archive_dir" --strip-components 1; then
        error "Failed to extract $archive_dir.$archive_ext"
    fi
}

# Helper function for building and installing
build_and_install() {
    local archive_dir=$1
    local LDFLAGS=$2
    cd "$cwd/$archive_dir" || exit 1
    mkdir -p build
    cd build || exit 1

    log "Configuring $archive_dir..."
    if ! ../configure --prefix="$install_dir/$archive_dir" --enable-static --with-pic "$LDFLAGS"; then
        error "Failed to configure $archive_dir"
    fi

    log "Building $archive_dir..."
    if ! make "-j$(nproc --all)"; then
        error "Failed to run make -j$(nproc --all)"
    fi

    log "Installing $archive_dir..."
    if ! sudo make install; then
        error "Failed to run make install"
    fi

    if ! sudo libtool --finish "$install_dir/$archive_dir/lib"; then
        error "Failed to finish libtool setup"
    fi

    log "Creating symlinks..."
    for file in "$install_dir"/"$archive_dir"/bin/*; do
        local filename
        filename=$(basename "$file")
        local linkname
        linkname=${filename#*-}
        sudo ln -sf "$file" "/usr/local/bin/$linkname" || warn "Failed to create symlink for $filename"
    done
}

# Main script execution
if [ "$EUID" -eq 0 ]; then
    error "You must run this script without root or with sudo."
fi

log "gettext + libiconv build script - v$script_ver"
echo "==============================================="

download_and_extract "$archive_dir1" "$archive_url1"
build_and_install "$archive_dir1"

download_and_extract "$archive_dir2" "$archive_url2"
build_and_install "$archive_dir2"

echo
log "Removing leftover files"
sudo rm -fr "$cwd"

echo
log "Build and installation completed successfully!"

