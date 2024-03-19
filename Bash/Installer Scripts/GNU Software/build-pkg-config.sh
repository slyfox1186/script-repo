#!/usr/bin/env bash

# Purpose: Build GNU pkg-config from source
# Updated: 03.06.24
# Script version: 1.5

set -euo pipefail

# ANSI color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Log functions
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}
warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}
fail() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check if the script is run as root
if [[ "$EUID" -eq 0 ]]; then
    fail "This script should not be run as root or with sudo."
fi

PROGRAM_NAME="pkg-config"
VERSION="0.29.2"
CWD="$PWD"
BUILD_DIR="$CWD/pkg-config-build"
INSTALL_DIR="/usr/local/$PROGRAM_NAME-$VERSION"

CC=gcc
CXX=g++
CFLAGS="-g -O3 -pipe -fno-plt -march=native"
CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CC CFLAGS CXX CXXFLAGS

PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"
export PATH

PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/share/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/lib/pkgconfig\
"
export PKG_CONFIG_PATH

# Dependencies required to build pkg-config
DEPENDENCIES=(autoconf autoconf-archive autogen automake build-essential
              ca-certificates ccache clang curl libssl-dev zlib1g-dev)

# Function to check and install missing dependencies
install_dependencies() {
    local to_install=()
    for dep in "${DEPENDENCIES[@]}"; do
        if ! dpkg -l | grep -qw "$dep"; then
            to_install+=("$dep")
        fi
    done
    if [ "${#to_install[@]}" -gt 0 ]; then
        log "Installing missing dependencies: ${to_install[*]}"
        sudo apt-get update && sudo apt-get install -y "${to_install[@]}"
    else
        log "All dependencies are satisfied."
    fi
}

# Function for cleanup
cleanup() {
    echo
    read -p "Do you want to clean up the build files? [y/N] " response
    case "$response" in
        [yY]*|"") rm -rf "$BUILD_DIR"
                  echo
                  log "Cleanup completed."
                  ;;
        [nN]*|*) echo
                 log "Cleanup skipped."
                 ;;
    esac
}

# Main function to build pkg-config
build_pkg_config() {
    local archive_url="https://pkgconfig.freedesktop.org/releases/pkg-config-$VERSION.tar.gz"

    # Download and extract source
    mkdir -p "$BUILD_DIR/pkg-config-$VERSION/build"
    curl -Lso "$BUILD_DIR/pkg-config-$VERSION.tar.gz" "$archive_url"
    tar -zxf "$BUILD_DIR/pkg-config-$VERSION.tar.gz" -C "$BUILD_DIR/pkg-config-$VERSION" --strip-components 1
    cd "$BUILD_DIR/pkg-config-$VERSION" || exit 1

    # Build and install
    autoconf
    cd build || exit 1
    ../configure --prefix="$INSTALL_DIR" \
                 --enable-indirect-deps \
                 --with-internal-glib \
                 --with-pc-path="$PKG_CONFIG_PATH" \
                 --with-pic \
                 PKG_CONFIG=$(type -P pkg-config)
    make "-j$(nproc)"
    sudo make install

    # Create symbolic links in /usr/local/bin
    find "$INSTALL_DIR/bin" -type f -exec sudo ln -sf {} /usr/local/bin \;
}

log "Starting build of GNU pkg-config $VERSION"

# Ensure the script is not run with sudo
if [ "$(id -u)" -eq 0 ]; then
    fail "Do not run this script as root. Use normal user privileges."
fi

install_dependencies
build_pkg_config
cleanup

log "GNU pkg-config $VERSION has been successfully built and installed."
