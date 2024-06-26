#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-pkg-config.sh
##  Purpose: build gnu pkg-config
##  Updated: 09.19.24
##  Script version: 1.3

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set variables
script_ver=1.3
archive_dir="pkg-config-0.29.2"
archive_url="https://pkgconfig.freedesktop.org/releases/$archive_dir.tar.gz"
archive_name="${archive_dir}.tar.${archive_url##*.}"
cwd="$PWD/pkg-config-build-script"
install_dir="/usr/local/programs/$archive_dir"

# Create logging functions
log() {
    echo -e "${GREEN}[INFO] Bash:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING] Bash:${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR] Bash:${NC} $1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Check if running as root or with sudo
if [[ "$EUID" -eq 0 ]]; then
    fail "You must run this script without root or sudo."
fi

log "pkg-config build script version $script_ver"
echo "==============================================="
echo

# Set the c + cpp compilers
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
export CC CFLAGS CXX CXXFLAGS

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

# Create functions
exit_fn() {
    log "Make sure to star this repository to show your support!"
    log "https://github.com/slyfox1186/script-repo"
    exit 0
}

cleanup() {
    local choice

    echo
    echo -e "${GREEN}============================================${NC}"
    echo -e "  ${YELLOW}Do you want to clean up the build files?${NC}  "
    echo -e "${GREEN}============================================${NC}"
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choices are (1 or 2): " choice

    case "$choice" in
        1) sudo rm -fr "$cwd";;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

# Install required apt packages
pkgs=("$1" autoconf autoconf-archive autogen automake build-essential ca-certificates ccache clang curl \
      libaria2-0 libaria2-0-dev libc-ares-dev libdmalloc-dev libgcrypt20-dev libgmp-dev libgnutls28-dev \
      libgpg-error-dev libjemalloc-dev libmbedtls-dev libnghttp2-dev librust-openssl-dev libsqlite3-dev \
      libssh2-1-dev libssh-dev libssl-dev libxml2-dev pkg-config zlib1g-dev)

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
cd "$cwd/$archive_dir/build" || fail "Failed to change directory to: $cwd/$archive_dir/build"
../configure --prefix="$install_dir" \
             --enable-indirect-deps \
             --with-internal-glib \
             --with-pc-path="$PKG_CONFIG_PATH" \
             --with-pic
make "-j$(nproc --all)"
if ! sudo make install; then
    fail "Failed to execute: sudo make install. Line: ${LINENO}"
fi

# Create soft links
sudo ln -sf "$install_dir/bin/pkg-config" "/usr/local/bin/pkg-config"

# Prompt user to clean up files
cleanup

# Show exit message
exit_fn