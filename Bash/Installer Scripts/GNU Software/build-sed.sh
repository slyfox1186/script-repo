#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-sed
##  Purpose: build gnu sed
##  Updated: 02.03.24
##  Script version: 1.1

set -euo pipefail

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Set variables
script_ver=1.1
archive_dir="sed-4.9"
archive_url="https://ftp.gnu.org/gnu/sed/$archive_dir.tar.xz"
archive_name="$archive_dir.tar.${archive_url##*.}"
cwd="$PWD/sed-build-script"
install_dir="/usr/local/$archive_dir"

[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

# Create logging functions
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

fail() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Check if running as root or with sudo
if [[ "$EUID" -eq 0 ]]; then
    fail "You must run this script without root or with sudo."
fi

echo
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}            Sed build script - v${script_ver}"
echo -e "${GREEN}===============================================${NC}"
echo

# Set the C and C++ compilers
CC="gcc"
CXX="g++"
CFLAGS="-O3 -pipe -fno-plt -march=native -mtune=native -D_FORTIFY_SOURCE=2"
CXXFLAGS="$CFLAGS"
LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
export CC CFLAGS CXX CXXFLAGS LDFLAGS

# Set the path variable
PATH="/usr/lib/ccache:${HOME}/perl5/bin:${HOME}/.cargo/bin:${HOME}/.local/bin:/usr/local/sbin:/usr/local/cuda/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

# Set the pkg_config_path variable
PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_PATH

# Create functions
exit_fn() {
    echo
    log "Make sure to star this repository to show your support!"
    log "https://github.com/slyfox1186/script-repo"
    exit 0
}

cleanup() {
    local choice
    echo
    read -p "Remove temporary build directory '$cwd'? [y/N] " choice
    case "$choice" in
        [yY]*|"")
        sudo rm -rf "$cwd"
        log "Build directory removed."
        ;;
        [nN]*) ;;
    esac
}

# Install required apt packages
pkgs=(
    autoconf autoconf-archive autogen automake autopoint autotools-dev build-essential bzip2
    ccache curl git libaudit-dev libintl-perl libticonv-dev libtool libtool-bin lzip pkg-config
    valgrind zlib1g-dev librust-polling-dev
)

missing_pkgs=""
for pkg in "${pkgs[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        missing_pkgs+=" $pkg"
    fi
done

if [[ -n "$missing_pkgs" ]]; then
    sudo apt install $missing_pkgs
fi

# Download the archive file
if [[ ! -f "$cwd/$archive_name" ]]; then
    curl -Lso "$cwd/$archive_name" "$archive_url"
fi

# Create output directory
[[ -d "$cwd/$archive_dir" ]] && sudo rm -fr "$cwd/$archive_dir"
mkdir -p "$cwd/$archive_dir/build"

# Extract archive files
if ! tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    fail "Failed to extract: $cwd/$archive_name"
fi

# Build program from source
cd "$cwd/$archive_dir" || fail "Failed to change directory to: $cwd/$archive_dir/build"
autoreconf -fi
cd build || exit 1
../configure --prefix="$install_dir" \
             --enable-threads=posix \
             --disable-nls \
             --with-libiconv-prefix=/usr \
             --with-libintl-prefix=/usr
if ! make "-j$(nproc --all)"; then
    fail "Failed to execute: make -j$(nproc --all). Line: $LINENO"
fi
if ! sudo make install; then
    fail "Failed to execute: sudo make install. Line: $LINENO"
fi

# Create soft links
sudo ln -sf "$install_dir"/bin/* /usr/local/bin/

# Prompt user to clean up files
cleanup

# Show exit message
exit_fn
