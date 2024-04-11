#!/usr/bin/env bash

set -euo pipefail

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-make
##  Purpose: build gnu make
##  Updated: 04.11.24
##  Script version: 2.1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
script_ver="2.1"
archive_dir="make-4.4.1"
archive_url="https://ftp.gnu.org/gnu/make/make-4.4.1.tar.lz"
archive_ext="${archive_url##*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/make-build-script"
install_dir="/usr/local/$archive_dir"
make_version=""

# Functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "${GREEN}[INFO]${NC} To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
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
        *) warn "Invalid choice. Skipping cleanup." ;;
    esac
}

install_dependencies() {
    log "Installing dependencies..."
    local pkgs=(
            autoconf autoconf-archive autogen automake binutils build-essential ccache cmake curl git
            guile-3.0-dev libdmalloc-dev libgmp-dev libtool libtool-bin lzip m4 nasm ninja-build texinfo
            zlib1g-dev yasm
        )

    local missing_pkgs=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        sudo apt-get update
        sudo apt-get install -y "${missing_pkgs[@]}"
        sudo apt-get -y autoremove
    fi
}

show_usage() {
    echo "Usage: ${0##*/} [OPTIONS]"
    echo "Build GNU Make from source."
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -v, --version    Specify the version of make to build (default: 4.4.1)"
    echo
    echo "Example:"
    echo "  $0 -v 4.3 -c"
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            shift
            make_version="$1"
            ;;
        *)
            warn "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    shift
done

# Update variables based on make version
if [ -n "$make_version" ]; then
    archive_dir="make-$make_version"
    archive_url="https://ftp.gnu.org/gnu/make/make-$make_version.tar.lz"
    archive_name="$archive_dir.tar.$archive_ext"
    install_dir="/usr/local/$archive_dir"
fi

# Set compiler and flags
CC="ccache gcc"
CXX="ccache g++"
CFLAGS="-O2 -pipe -fno-plt -march=native -mtune=native -D_FORTIFY_SOURCE=2"
CXXFLAGS="$CFLAGS"
LDFLAGS="-Wl,-rpath=/usr/local/lib64:/usr/local/lib"
export CC CXX CFLAGS CXXFLAGS LDFLAGS

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
mkdir -p "$cwd/$archive_dir/build"

# Download archive
if [ ! -f "$cwd/$archive_name" ]; then
    curl -LSso "$cwd/$archive_name" "$archive_url"
else
    log "Archive already exists: $cwd/$archive_name"
fi

# Extract archive
tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1 || fail "Failed to extract archive"

# Build and install
cd "$cwd/$archive_dir" || fail "Failed to change directory to $cwd/$archive_dir"
autoreconf -fi -I /usr/share/aclocal
cd build || fail "Failed to change directory to build"
../configure --prefix="$install_dir" \
             --disable-nls \
             --enable-year2038 \
             --with-dmalloc \
             --with-libsigsegv-prefix=/usr \
             --with-libiconv-prefix=/usr \
             --with-libintl-prefix=/usr \
             PKG_CONFIG="$(type -P pkg-config)"
make "-j$(nproc --all)" || fail "Failed to build make"
sudo make install || fail "Failed to install make"

# Create symlinks
for dir in bin include; do
    for file in "$install_dir"/$dir/*; do
        filename="${file##*/}"
        sudo ln -sf "$file" "/usr/local/$dir/$filename" || warn "Failed to create symlink for $filename"
    done
done

# Cleanup files
cleanup

echo
log "make build script completed successfully!"
log "Make sure to star this repository to show your support: https://github.com/slyfox1186/script-repo"
