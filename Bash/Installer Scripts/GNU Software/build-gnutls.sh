#!/usr/bin/env bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
script_ver=2.0
archive_dir=guile-gnutls-4.0.0
archive_url=https://ftp.gnu.org/gnu/gnutls/$archive_dir.tar.gz
archive_ext="${archive_url##*.}"
archive_name="$archive_dir.tar.$archive_ext"
install_dir="/usr/local/$archive_dir"
cwd="$PWD/gnutls-build-script"
web_repo=https://github.com/slyfox1186/script-repo

# Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

fail() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo -e "${RED}To report a bug create an issue at: $web_repo/issues${NC}"
    exit 1
}

cleanup() {
    local choice
    echo "============================================"
    echo "  Do you want to clean up the build files?  "
    echo "============================================"
    echo "[1] Yes"
    echo "[2] No"
    read -p 'Your choice (1 or 2): ' choice

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
    local pkgs=("$1" autoconf autoconf-archive autogen automake binutils build-essential ccache
                cmake curl guile-3.0-dev git libgmp-dev libintl-perl libtool libtool-bin m4 nasm
                ninja-build texinfo zlib1g-dev yasm)
    local missing_pkgs=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        apt-get update
        apt-get install ${missing_pkgs[@]}
    fi
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    fail "You must run this script without root or sudo."
fi

# Print banner
log "gnutls build script - v$script_ver"
echo "========================================"
echo

# Create working directory
log "Creating working directory..."
mkdir -p "$cwd"

# Set compiler and flags
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
export CC CXX CFLAGS CXXFLAGS

# Set PATH and PKG_CONFIG_PATH
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

# Download archive
if [ ! -f "$cwd/$archive_name" ]; then
    log "Downloading $archive_url..."
    curl -Lso "$cwd/$archive_name" "$archive_url"
else
    log "Archive already exists: $cwd/$archive_name"
fi

# Extract archive
log "Extracting archive..."
mkdir -p "$cwd/$archive_dir/build"
tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1 || fail "Failed to extract: $cwd/$archive_name"

# Build and install
log "Building and installing gnutls..."
cd "$cwd/$archive_dir" || fail "Failed to change directory to $cwd/$archive_dir"
autoreconf -fi
cd build || fail "Failed to change directory to build"

../configure --prefix="$install_dir" \
             --disable-nls \
             --enable-static \
             --enable-shared \
             --with-pic \
             PKG_CONFIG="$(command -v pkg-config)" \
             PKG_CONFIG_PATH="$PKG_CONFIG_PATH" \
             CC="$CC"

make "-j$(nproc --all)" || fail "Failed to build gnutls"
make install || fail "Failed to install gnutls"

# Create symlinks
log "Creating symlinks..."
for file in "$install_dir/bin/"*; do
    filename=$(basename "$file")
    linkname=${filename#*-}
    ln -sf "$file" "/usr/local/bin/$linkname" || warn "Failed to create symlink for $filename"
done

# Cleanup
cleanup

log "gnutls build script completed successfully!"
log "Make sure to star this repository to show your support!"
log "$web_repo"
