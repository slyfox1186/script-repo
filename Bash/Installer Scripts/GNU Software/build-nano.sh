#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-nano
##  Purpose: build gnu nano
##  Updated: 08.03.23
##  Script version: 2.0

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
script_ver="2.0"
archive_dir="nano-7.2"
archive_url="https://ftp.gnu.org/gnu/nano/nano-7.2.tar.xz"
archive_ext="${archive_url##*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/nano-build-script"
install_dir="/usr/local/$archive_dir"
web_repo="https://github.com/slyfox1186/script-repo"

# Functions
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "\\n${YELLOW}[WARNING] $1${NC}\\n"
}

fail() {
    echo -e "\\n${RED}[ERROR] $1${NC}"
    echo -e "${RED}To report a bug, create an issue at: $web_repo/issues${NC}\\n"
    exit 1
}

cleanup() {
    if sudo rm -fr "$cwd"; then
        echo
        log "The build files were removed successfully."
    else
        echo
        log "The build files failed to remove."
    fi
}

install_dependencies() {
    log "Installing dependencies..."
    echo
    local pkgs=(autoconf autoconf-archive autogen automake binutils bison build-essential bzip2 ccache curl
                libc6-dev libintl-perl libpth-dev libticonv-dev libtool libtool-bin lzip lzma-dev m4 nasm texinfo
                zlib1g-dev yasm)
    local missing_pkgs=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        apt-get update
        apt-get install -y "${missing_pkgs[@]}"
        apt-get -y autoremove
    fi
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Build GNU nano from source."
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -c, --cleanup    Clean up build files after installation"
    echo "  -v, --verbose    Enable verbose output"
    echo "  -s, --silent     Run silently (no output)"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    fail "You must run this script without root or sudo."
fi

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -c|--cleanup)
            cleanup_files=true
            ;;
        -v|--verbose)
            verbose=true
            ;;
        -s|--silent)
            silent=true
            ;;
        *)
            warn "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    shift
done

# Print banner
if [ "$silent" != true ]; then
    log "nano build script - v${script_ver}"
    log "======================================="
fi

# Set compiler and flags
export CC=gcc CXX=g++
export CFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CXXFLAGS="$CFLAGS"

# Set PATH and PKG_CONFIG_PATH
PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:\
/usr/local/cuda/bin:/usr/local/x86_64-linux-gnu/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:\
/bin:/usr/local/games:/usr/games:/snap/bin"
export PATH

PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/share/pkgconfig:/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig:/lib64/pkgconfig:\
/lib/pkgconfig:/lib/x86_64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH

# Install dependencies
install_dependencies

# Create working directory
if [ "$verbose" = true ]; then
    log "Creating working directory..."
fi
mkdir -p "$cwd"

# Download archive
if [ ! -f "$cwd/$archive_name" ]; then
    if [ "$verbose" = true ]; then
        log "Downloading $archive_url..."
    fi
    curl -Lso "$cwd/$archive_name" "$archive_url"
else
    if [ "$verbose" = true ]; then
        log "Archive already exists: $cwd/$archive_name"
    fi
fi

# Extract archive
if [ "$verbose" = true ]; then
    log "Extracting archive..."
    echo
fi
mkdir -p "$cwd/$archive_dir/build"
tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1 || fail "Failed to extract archive"

# Build and install
cd "$cwd/$archive_dir" || fail "Failed to change directory to $cwd/$archive_dir"
autoreconf -fi
cd build || fail "Failed to change directory to build"

../configure --prefix="$install_dir" \
             --build=x86_64-linux-gnu \
             --host=x86_64-linux-gnu \
             --disable-nls \
             --enable-threads=posix \
             --enable-utf8 \
             --enable-year2038 \
             --with-libiconv-prefix=/usr \
             --with-libintl-prefix=/usr \
             PKG_CONFIG="$(command -v pkg-config)" \
             PKG_CONFIG_PATH="$PKG_CONFIG_PATH"

if [ "$verbose" = true ]; then
    log "Building and installing nano..."
    make "-j$(nproc --all)" || fail "Failed to build nano"
else
    make "-j$(nproc --all)" >/dev/null 2>&1 || fail "Failed to build nano"
fi

sudo make install >/dev/null 2>&1 || fail "Failed to install nano"

# Create symlinks
if [ "$verbose" = true ]; then
    log "Creating symlinks..."
fi
for file in "$install_dir"/bin/*; do
    filename=$(basename "$file")
    linkname=${filename#*-}
    sudo ln -sf "$file" "/usr/local/bin/$linkname" || warn "Failed to create symlink for $filename"
done

# Cleanup if requested
if [ "$cleanup_files" = true ]; then
    cleanup
fi

if [ "$silent" != true ]; then
    echo
    log "nano build script completed successfully!"
    log "Make sure to star this repository to show your support: $web_repo"
fi