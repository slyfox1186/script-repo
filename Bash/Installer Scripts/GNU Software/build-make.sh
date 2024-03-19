#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-make
##  Purpose: build gnu make
##  Updated: 08.01.23
##  Script version: 2.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
script_ver="2.0"
archive_dir="make-4.4.1"
archive_url="https://ftp.gnu.org/gnu/make/make-4.4.1.tar.lz"
archive_ext="${archive_url##*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/make-build-script"
install_dir="/usr/local/$archive_dir"
web_repo="https://github.com/slyfox1186/script-repo"

# Functions
log() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

fail() {
    echo -e "${RED}ERROR: $1${NC}"
    echo -e "${RED}To report a bug, create an issue at: $web_repo/issues${NC}"
    exit 1
}

cleanup() {
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
}

install_dependencies() {
    log "Installing dependencies..."
    local pkgs=(autoconf autoconf-archive autogen automake binutils build-essential ccache cmake curl git guile-3.0-dev libdmalloc-dev libdmalloc5 libgmp-dev libintl-perl libmpfr-dev libreadline-dev libsigsegv-dev libticonv-dev libtool libtool-bin lzip m4 nasm ninja-build texinfo zlib1g-dev yasm)
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
    echo "Build GNU Make from source."
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -c, --cleanup    Clean up build files after installation"
    echo "  -v, --verbose    Enable verbose output"
    echo "  -s, --silent     Run silently (no output)"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    fail "You must run this script with root or sudo."
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
    log "make build script - v${script_ver}"
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

PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig:/lib64/pkgconfig:/lib/pkgconfig:/lib/x86_64-linux-gnu/pkgconfig"
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
fi
mkdir -p "$cwd/$archive_dir/build"
tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1 || fail "Failed to extract archive"

# Build and install
cd "$cwd/$archive_dir" || fail "Failed to change directory to $cwd/$archive_dir"
autoreconf -fi -I /usr/share/aclocal
cd build || fail "Failed to change directory to build"

if [ "$verbose" = true ]; then
    log "Building and installing make..."
    ../configure --prefix="$install_dir" \
                 --disable-nls \
                 --enable-year2038 \
                 --with-dmalloc \
                 --with-libsigsegv-prefix=/usr \
                 --with-libiconv-prefix=/usr \
                 --with-libintl-prefix=/usr \
                 PKG_CONFIG="$(command -v pkg-config)"
    make "-j$(nproc --all)" || fail "Failed to build make"
    make install || fail "Failed to install make"
else
    ../configure --prefix="$install_dir" \
                 --disable-nls \
                 --enable-year2038 \
                 --with-dmalloc \
                 --with-libsigsegv-prefix=/usr \
                 --with-libiconv-prefix=/usr \
                 --with-libintl-prefix=/usr \
                 PKG_CONFIG="$(command -v pkg-config)" >/dev/null 2>&1
    make "-j$(nproc --all)" >/dev/null 2>&1 || fail "Failed to build make"
    make install >/dev/null 2>&1 || fail "Failed to install make"
fi

# Create symlinks
if [ "$verbose" = true ]; then
    log "Creating symlinks..."
fi
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
    log "make build script completed successfully!"
    log "Make sure to star this repository to show your support: $web_repo"
fi