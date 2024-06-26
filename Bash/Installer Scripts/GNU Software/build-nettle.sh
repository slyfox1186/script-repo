#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-nettle
##  Purpose: build gnu nettle
##  Updated: 08.01.23
##  Script version: 2.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
script_ver="2.0"
archive_dir="nettle-3.9.1"
archive_url="https://ftp.gnu.org/gnu/nettle/nettle-3.9.1.tar.gz"
archive_ext="${archive_url##*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/nettle-build-script"
install_dir="/usr/local/programs/$archive_dir"

# Functions
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

fail() {
    echo -e "${RED}[ERROR] $1${NC}"
    warn "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

cleanup() {
    if sudo rm -fr "$cwd"; then
        log "The build files were removed successfully."
    else
        warn "The build files failed to remove."
    fi
}

install_dependencies() {
    log "Installing dependencies..."
    local pkgs=(autoconf autoconf-archive autogen automake
                build-essential ccache curl gcovr git libtool
                m4 zlib1g-dev)
    local missing_pkgs=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        sudo apt-get update
        sudo apt-get install "${missing_pkgs[@]}"
    fi
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Build GNU nettle from source."
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
    log "nettle build script - v${script_ver}"
    log "======================================="
fi

# Set compiler and flags
CC="gcc"
CXX="g++"
CFLAGS="-O3 -pipe -march=native"
CXXFLAGS="$CFLAGS"
export CC CFLAGS CXX CXXFLAGS

# Set PATH and PKG_CONFIG_PATH
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

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
fi
mkdir -p "$cwd/$archive_dir/build"
tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1 || fail "Failed to extract archive"

# Build and install
cd "$cwd/$archive_dir" || fail "Failed to change directory to $cwd/$archive_dir"
autoreconf -fi
cd build || fail "Failed to change directory to build"

../configure --prefix="$install_dir" --disable-documentation --enable-gcov

if [ "$verbose" = true ]; then
    log "Building and installing nettle..."
    make "-j$(nproc --all)" || fail "Failed to build nettle"
else
    make "-j$(nproc --all)" >/dev/null 2>&1 || fail "Failed to build nettle"
fi

sudo make install >/dev/null 2>&1 || fail "Failed to install nettle"

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
    log "nettle build script completed successfully!"
    log "Make sure to star this repository to show your support: https://github.com/slyfox1186/script-repo"
fi
