#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-grep
##  Purpose: build gnu grep
##  Updated: 08.13.23
##  Script version: 2.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
script_ver="2.0"
archive_dir="grep-3.11"
archive_url="https://ftp.gnu.org/gnu/grep/grep-3.11.tar.xz"
archive_ext="${archive_url##*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/grep-build-script"
install_dir="/usr/local/$archive_dir"
web_repo="https://github.com/slyfox1186/script-repo"

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
    local answer
    echo -e "\n${YELLOW}============================================${NC}"
    echo -e "${YELLOW}  Do you want to clean up the build files?  ${NC}"
    echo -e "${YELLOW}============================================${NC}"
    echo -e "[1] Yes"
    echo -e "[2] No"
    read -p "Your choice (1 or 2): " answer

    case "$answer" in
        1) rm -fr "$cwd";;
        2) log "Skipping cleanup.";;
        *)
            warn "Invalid choice. Skipping cleanup."
            ;;
    esac
}

install_dependencies() {
    log "Installing dependencies..."
    local pkgs=(autoconf autoconf-archive autogen automake binutils build-essential ccache cmake curl git libgmp-dev libintl-perl libmpfr-dev libreadline-dev libsigsegv-dev libticonv-dev libtool libtool-bin lzip m4 nasm ninja-build texinfo zlib1g-dev yasm)
    local missing_pkgs=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        apt-get update
        apt-get install -y ${missing_pkgs[@]}
        apt-get -y autoremove
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    fail "You must run this script with root/sudo."
fi

# Print banner
log "grep build script - v$script_ver"
echo -e "${GREEN}===============================================${NC}"

# Install dependencies
install_dependencies

# Create working directory
log "Creating working directory..."
mkdir -p "$cwd"

# Set compiler and flags
CC="gcc"
CXX="g++"
CFLAGS="-O3 -pipe -fno-plt -march=native"
CXXFLAGS="-O3 -pipe -fno-plt -march=native"
export CC CFLAGS CXX CXXFLAGS

# Set PATH and PKG_CONFIG_PATH
PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:/sbin:\
/bin\
"
export PATH

PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/share/pkgconfig\
"
export PKG_CONFIG_PATH


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
log "Building and installing grep..."
cd "$cwd/$archive_dir" || fail "Failed to change directory to $cwd/$archive_dir"
autoreconf -fi
cd build || fail "Failed to change directory to build"

../configure --prefix="$install_dir" \
             --disable-nls \
             --enable-gcc-warnings=no \
             --enable-threads=posix \
             --with-libsigsegv \
             --with-libsigsegv-prefix=/usr \
             --with-libiconv-prefix=/usr \
             --with-libintl-prefix=/usr \
             PKG_CONFIG="$(command -v pkg-config)" \
             PKG_CONFIG_PATH="$PKG_CONFIG_PATH"

make "-j$(nproc --all)" || fail "Failed to build grep"
make install || fail "Failed to install grep"

# Create symlinks
log "Creating symlinks..."
for file in "$install_dir"/bin/*; do
    filename=$(basename "$file")
    linkname=${filename#*-}
    ln -sf "$file" "/usr/local/bin/$linkname" || warn "Failed to create symlink for $filename"
done

# Cleanup
cleanup

log "grep build script completed successfully!"
log "Make sure to star this repository to show your support!"
log "$web_repo"