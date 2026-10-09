#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Ee -o pipefail
trap 'printf "Build failed at line %s. Build files were retained for inspection.\n" "$LINENO" >&2; exit 1' ERR

gnu_curl() {
    command curl -q --fail --location --show-error --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 600 --proto '=https' --proto-redir '=https' \
        --user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$@"
}

gnu_link_dir() {
    local source_dir="$1" destination="$2" pattern="${3:-*}" file target
    [[ -d "$source_dir" ]] || return 0
    for file in "$source_dir"/*; do
        [[ -e "$file" || -L "$file" ]] || continue
        # The caller supplies a filename glob, for example *.pc.
        # shellcheck disable=SC2053
        [[ "${file##*/}" == $pattern ]] || continue
        target="$destination/${file##*/}"
        [[ ! -d "$target" || -L "$target" ]] || { printf 'Cannot replace directory %s with a symlink.\n' "$target" >&2; return 1; }
        sudo mkdir -p -- "$destination"
        sudo ln -sfn -- "$file" "$target"
    done
}

gnu_new_workdir() {
    local base="${TMPDIR:-/tmp}"
    [[ "$base" == /* && -d "$base" ]] || { printf 'TMPDIR must be an existing absolute directory.\n' >&2; return 1; }
    mktemp -d -- "$base/${0##*/}.XXXXXX"
}

gnu_jobs="${JOBS:-$(nproc)}"
[[ "$gnu_jobs" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer.\n' >&2; exit 1; }

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
working=""
install_dir="/usr/local/programs/$program_name-$version"

CC="ccache gcc"
CXX="ccache g++"
CFLAGS="-O2 -pipe -fno-plt -march=native -mtune=native"
CXXFLAGS="$CFLAGS"
export CC CFLAGS CXX CXXFLAGS

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

# dependencies required to build pkg-config
dependencies=(
        autoconf autoconf-archive autogen automake build-essential
        ca-certificates ccache clang curl libssl-dev zlib1g-dev
    )

# Function to check and install missing dependencies
install_dependencies() {
    local to_install=()
    for dep in "${dependencies[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q "ok installed"; then
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
    local response
    while true; do
        if ! read -r -p "Remove build directory '$cwd'? [y/N] " response; then
            printf '\nBuild files retained at %s\n' "$cwd"
            return 0
        fi
        case "$response" in
            1|y|Y|yes|YES) rm -rf -- "$cwd"; return 0 ;;
            2|n|N|no|NO|"") printf 'Build files retained at %s\n' "$cwd"; return 0 ;;
            *) printf 'Enter y or n.\n' >&2 ;;
        esac
    done
}

# Main function to build pkg-config
build_pkg_config() {
    local archive_url="https://pkgconfig.freedesktop.org/releases/pkg-config-$version.tar.gz"

    # Download and extract source
    cwd=$(gnu_new_workdir)
    working="$cwd/working"
    mkdir -p "$working/pkg-config-$version/build"
    gnu_curl -Lso "$working/pkg-config-$version.tar.gz" "$archive_url"
    tar -zxf "$working/pkg-config-$version.tar.gz" -C "$working/pkg-config-$version" --strip-components 1
    cd "$working/pkg-config-$version" || exit 1

    # Build and install

    cd build || exit 1
    ../configure --prefix="$install_dir" \
                 --enable-indirect-deps \
                 --with-internal-glib \
                 --with-pc-path="$PKG_CONFIG_PATH" \
                 --with-pic
    make "-j$gnu_jobs"
    sudo make install

    # Create symbolic links in /usr/local/bin
    gnu_link_dir "$install_dir/bin" /usr/local/bin
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
