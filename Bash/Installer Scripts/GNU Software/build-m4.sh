#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-m4.sh
##  Purpose: build gnu m4
##  Updated: 02.20.24
##  Script version: 2.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
script_ver="2.0"
archive_dir="m4-latest"
archive_url="https://ftp.gnu.org/gnu/m4/m4-latest.tar.xz"
archive_ext="${archive_url##*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/m4-build-script"
install_dir="/usr/local/m4-latest"

# Functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "${RED}To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues${NC}"
    exit 1
}

cleanup() {
    local choice
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Do you want to clean up the build files?  ${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
    echo -e "[1] Yes"
    echo -e "[2] No"
    echo
    read -p "Your choice (1 or 2): " choice

    case "$choice" in
        1) sudo rm -fr "$cwd" ;;
        2) log "Skipping cleanup." ;;
        *) warn "Invalid choice. Skipping cleanup."
           ;;
    esac
}

install_dependencies() {
    log "Installing dependencies..."
    local pkgs=(
            autoconf autoconf-archive autogen automake binutils bison build-essential bzip2
            ccache curl libc6-dev libpth-dev libtool libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev yasm
        )
    local missing_pkgs=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        sudo apt update
        sudo apt install -y "${missing_pkgs[@]}"
        sudo apt -y autoremove
    fi
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Build GNU m4 from source."
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -v, --verbose    Enable verbose output"
    echo "  -s, --silent     Run silently (no output)"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    fail "You must run this script without root or with sudo."
fi

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
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
    log "m4 build script - v${script_ver}"
    log "======================================="
fi

# Set compiler and flags
CC="ccache gcc"
CXX="ccache g++"
CFLAGS="-O2 -pipe -fno-plt -march=native -mtune=native"
CXXFLAGS="$CFLAGS"
export CC CFLAGS CXX CXXFLAGS

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
cd "$cwd/$archive_dir/build" || fail "Failed to change directory to $cwd/$archive_dir/build"
if [ "$verbose" = true ]; then
    log "Building m4..."
    ../configure --prefix="$install_dir" \
                 --disable-nls \
                 --disable-gcc-warnings \
                 --enable-c++ \
                 --enable-threads=posix \
                 --with-dmalloc
    make "-j$(nproc --all)" || fail "Failed to build m4"
    log "Installing m4..."
    sudo make install || fail "Failed to install m4"
else
    ../configure --prefix="$install_dir" \
                 --disable-nls \
                 --disable-gcc-warnings \
                 --enable-c++ \
                 --enable-threads=posix \
                 --with-dmalloc
    make "-j$(nproc --all)" || fail "Failed to build m4"
    sudo make install || fail "Failed to install m4"
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
cleanup

if [ "$silent" != true ]; then
    log "m4 build script completed successfully!"
    log "Make sure to star this repository to show your support: https://github.com/slyfox1186/script-repo"
fi
