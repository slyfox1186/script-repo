#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Ee -o pipefail
trap 'printf "Build failed at line %s. Build files were retained for inspection.\n" "$LINENO" >&2; exit 1' ERR

gnu_new_workdir() {
    local base="${TMPDIR:-/tmp}"
    [[ "$base" == /* && -d "$base" ]] || { printf 'TMPDIR must be an existing absolute directory.\n' >&2; return 1; }
    mktemp -d -- "$base/${0##*/}.XXXXXX"
}

gnu_jobs="${JOBS:-$(nproc)}"
[[ "$gnu_jobs" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer.\n' >&2; exit 1; }

## Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/installer-scripts/gnu-software/build-isl
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
install_dir="/usr/local/programs/$archive_dir"

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
        echo -e "${RED}To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues${NC}"
    fi
    exit 1
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
        sudo apt-get update
        sudo apt-get install -y "${missing_pkgs[@]}"
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
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
# Set PATH and PKG_CONFIG_PATH
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export CC CXX CFLAGS CPPFLAGS CXXFLAGS PATH PKG_CONFIG_PATH

# Install dependencies
install_dependencies

# Create working directory
log "Creating working directory..."
cwd=$(gnu_new_workdir)
mkdir -p "$cwd"

# Clone repository
log "Cloning repository..."
git clone "$archive_url" "$cwd/$archive_dir"
mkdir -p "$cwd/$archive_dir/build"

# Build and install
cd "$cwd/$archive_dir" || fail "Failed to enter the ISL source directory."
./autogen.sh
cd build || fail "Failed to enter the ISL build directory."
if [ "$verbose" = true ]; then
    log "Building and installing isl..."
    ../configure --prefix="$install_dir" \
                 --with-pic
    make "-j$gnu_jobs" || fail "Failed to build isl"
    sudo make install || fail "Failed to install isl"
else
    ../configure --prefix="$install_dir" \
                 --with-pic >/dev/null 2>&1
    make "-j$gnu_jobs" >/dev/null 2>&1 || fail "Failed to build isl"
    sudo make install >/dev/null 2>&1 || fail "Failed to install isl"
fi

# Create symlinks
log "Creating symlinks..."
for file in "$install_dir"/bin/*; do
    [[ -e "$file" || -L "$file" ]] || continue
    filename=$(basename "$file")
    linkname=$filename
    sudo ln -sf "$file" "/usr/local/bin/$linkname" || warn "Failed to create symlink for $filename"
done

# Cleanup if requested
if [ "$cleanup_files" = true ]; then
    cleanup
fi

if [ "$silent" != true ]; then
    log "isl build script completed successfully!"
    log "Make sure to star this repository to show your support: https://github.com/slyfox1186/script-repo"
fi
