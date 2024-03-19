#!/usr/bin/env bash

## Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-isl
## Purpose: build gnu isl
## Updated: 08.03.23
## Script version: 2.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
script_ver="2.0"
archive_dir="isl-git"
archive_url="https://repo.or.cz/isl.git"
cwd="$PWD/isl-build-script"
install_dir="/usr/local/$archive_dir"
web_repo="https://github.com/slyfox1186/script-repo"

# Functions
log() {
    if [ "$silent" != true ]; then
        echo -e "${GREEN}$1${NC}"
    fi
}

warn() {
    if [ "$silent" != true ]; then
        echo -e "${YELLOW}WARNING: $1${NC}"
    fi
}

fail() {
    if [ "$silent" != true ]; then
        echo -e "${RED}ERROR: $1${NC}"
        echo -e "${RED}To report a bug, create an issue at: $web_repo/issues${NC}"
    fi
    exit 1
}

cleanup() {
    if [ "$silent" != true ]; then
        local choice
        echo -e "${BLUE}============================================${NC}"
        echo -e "${BLUE}  Do you want to clean up the build files?  ${NC}"
        echo -e "${BLUE}============================================${NC}"
        echo -e "[1] Yes"
        echo -e "[2] No"
        read -p "Your choice (1 or 2): " choice

        case "$choice" in
            1) rm -fr "$cwd";;
            2) log "Skipping cleanup.";;
            *)
                warn "Invalid choice. Skipping cleanup."
                ;;
        esac
    else
        rm -fr "$cwd"
    fi
}

install_dependencies() {
    log "Installing dependencies..."
    local pkgs=(autoconf autoconf-archive autogen automake binutils build-essential ccache clang cmake
                curl git libclang-dev libtool libtool-bin llvm-dev lzip m4 nasm pkg-config zlib1g-dev yasm)
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
    echo "Build GNU isl from source."
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

# Print banner
if [ "$silent" != true ]; then
    log "isl build script - v${script_ver}"
    log "======================================="
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

# Set compiler and flags
export CC=gcc CXX=g++
export CFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CXXFLAGS="$CFLAGS"

# Set PATH and PKG_CONFIG_PATH
PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:\
/usr/local/cuda/bin:/usr/local/x86_64-linux-gnu/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:\
/bin:/usr/local/games:/usr/games:/snap/bin"
export PATH

PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig:/lib64/pkgconfig:/lib/pkgconfig:/lib/x86_64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH

# Install dependencies
install_dependencies

# Create working directory
log "Creating working directory..."
mkdir -p "$cwd"

# Clone repository
if [ -d "$cwd/$archive_dir" ]; then
    rm -fr "$cwd/$archive_dir"
fi
log "Cloning repository..."
git clone "$archive_url" "$cwd/$archive_dir"
mkdir -p "$cwd/$archive_dir/build"

# Build and install
if [ "$verbose" = true ]; then
    log "Building and installing isl..."
    ../configure --prefix="$install_dir" \
                 --build=x86_64-linux-gnu \
                 --host=x86_64-linux-gnu \
                 --with-pic
    make "-j$(nproc --all)" || fail "Failed to build isl"
    make install || fail "Failed to install isl"
else
    ../configure --prefix="$install_dir" \
                 --build=x86_64-linux-gnu \
                 --host=x86_64-linux-gnu \
                 --with-pic >/dev/null 2>&1
    make "-j$(nproc --all)" >/dev/null 2>&1 || fail "Failed to build isl"
    make install >/dev/null 2>&1 || fail "Failed to install isl"
fi

# Create symlinks
log "Creating symlinks..."
for file in "$install_dir"/bin/*; do
    filename=$(basename "$file")
    linkname=${filename#*-}
    ln -sf "$file" "/usr/local/bin/$linkname" || warn "Failed to create symlink for $filename"
done

# Cleanup if requested
if [ "$cleanup_files" = true ]; then
    cleanup
fi

if [ "$silent" != true ]; then
    log "isl build script completed successfully!"
    log "Make sure to star this repository to show your support: $web_repo"
fi
