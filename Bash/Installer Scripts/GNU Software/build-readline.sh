#!/usr/bin/env bash

#  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-readline
#  Purpose: build gnu readline
#  Updated: 03.19.24
#  Script version: 1.2

set -euo pipefail

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set variables
script_ver=1.2
archive_dir="readline-8.2"
archive_url="https://ftp.gnu.org/gnu/readline/$archive_dir.tar.gz"
archive_name="$archive_dir.tar.${archive_url##*.}"
cwd="$PWD/readline-build-script"
install_dir="/usr/local/$archive_dir"

[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

# Create logging functions
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

fail() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Check if running as root or with sudo
if [[ "$EUID" -eq 0 ]]; then
    fail "You must run this script without root or sudo."
fi

log "Readline build script - v${script_ver}"
echo "==============================================="
echo

# Set the C and C++ compilers
CC="gcc"
CXX="g++"
CFLAGS="-g -O3 -pipe -fno-plt -march=native"
CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CC CFLAGS CXX CXXFLAGS

# Set the path variable
PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/cuda/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

# Set the pkg_config_path variable
PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_PATH

# Create functions
exit_fn() {
    log "Make sure to star this repository to show your support!"
    log "${web_repo}"
    exit 0
}

cleanup() {
    local choice

    echo -e "\n${GREEN}============================================${NC}"
    echo -e "  ${YELLOW}Do you want to clean up the build files?${NC}  "
    echo -e "${GREEN}============================================${NC}"
    echo "[1] Yes"
    echo "[2] No"
    read -p "Your choice (1 or 2): " choice

    case "${choice}" in
        1) sudo rm -fr "$cwd";;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

# Install required apt packages
pkgs=(autoconf autoconf-archive autogen automake autopoint autotools-dev
      build-essential bzip2 ccache curl git libaudit-dev libintl-perl
      librust-polling-dev libtool lzip pkg-config valgrind zlib1g-dev)

missing_pkgs=""
for pkg in "${pkgs[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        missing_pkgs+=" $pkg"
    fi
done

if [[ -n "$missing_pkgs" ]]; then
    sudo apt-get install $missing_pkgs
fi

# Download the archive file
if [[ ! -f "$cwd/$archive_name" ]]; then
    curl -Lso "$cwd/$archive_name" "$archive_url"
fi

# Create output directory
[[ -d "$cwd/$archive_dir" ]] && sudo rm -fr "$cwd/$archive_dir"
mkdir -p "$cwd/$archive_dir/build"

# Extract archive files
if ! tar -zxf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    fail "Failed to extract: $cwd/$archive_name"
fi

# Build program from source
cd "$cwd/$archive_dir" || fail "Failed to change directory to: $cwd/$archive_dir"
autoconf
cd build || fail "Failed to change directory to: $cwd/$archive_dir/build"
../configure --prefix="$install_dir" \
             --disable-install-examples \
             --disable-shared \
             --enable-static
make "-j$(nproc --all)"
if ! sudo make install; then
    fail "Failed to execute: sudo make install. Line: ${LINENO}"
fi

sudo ldconfig "$install_dir/lib"

# Create soft links
sudo ln -sf "$install_dir/bin/readline" "/usr/local/bin/readline"

# Prompt user to clean up files
cleanup

# Show exit message
exit_fn