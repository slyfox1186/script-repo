#!/usr/bin/env bash

# Purpose: Build GNU pkg-config from source
# Updated: 03.06.24
# Script version: 1.5

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

program_name="pkg-config"
version="0.29.2"
cwd="$PWD/pkg-config-build"
working="$cwd/working"
install_dir="/usr/local/$program_name-$version"

CC="ccache gcc"
CXX="ccache g++"
CFLAGS="-O2 -pipe -fno-plt -march=native -mtune=native"
CXXFLAGS="$CFLAGS"
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

# dependencies required to build pkg-config
dependencies=(
        autoconf autoconf-archive autogen automake build-essential
        ca-certificates ccache clang curl libssl-dev zlib1g-dev
    )

# Function to check and install missing dependencies
install_dependencies() {
    local to_install=()
    for dep in "${dependencies[@]}"; do
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

cleanup() {
    local choice
    echo
    read -p "Remove temporary build directory '$cwd'? [y/N] " response
    case "$response" in
        [yY]*|"")
        sudo rm -rf "$cwd"
        log "Build directory removed."
        ;;
        [nN]*) ;;
    esac
}

# Main function to build pkg-config
build_pkg_config() {
    local archive_url="https://pkgconfig.freedesktop.org/releases/pkg-config-$version.tar.gz"

    # Download and extract source
    mkdir -p "$working/pkg-config-$version/build"
    curl -Lso "$working/pkg-config-$version.tar.gz" "$archive_url"
    tar -zxf "$working/pkg-config-$version.tar.gz" -C "$working/pkg-config-$version" --strip-components 1
    cd "$working/pkg-config-$version" || exit 1

    # Build and install
    autoconf
    cd build || exit 1
    ../configure --prefix="$install_dir" \
                 --enable-indirect-deps \
                 --with-internal-glib \
                 --with-pc-path="$PKG_CONFIG_PATH" \
                 --with-pic
    make "-j$(nproc)"
    sudo make install

    # Create symbolic links in /usr/local/bin
    find "$install_dir/bin" -type f -exec sudo ln -sf {} /usr/local/bin \;
}

log "Starting build of GNU pkg-config $version"

# Ensure the script is not run with sudo
if [[ "$EUID" -eq 0 ]]; then
    fail "You must run this script without root or with sudo."
fi

install_dependencies
build_pkg_config
cleanup

log "GNU pkg-config $version has been successfully built and installed."
