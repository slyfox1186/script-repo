#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-sed
##  Purpose: build gnu sed
##  Updated: 02.03.24
##  Script version: 1.1

set -euo pipefail

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

fail() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Check if running as root or with sudo
if [[ "$EUID" -ne 0 ]]; then
    fail "You must run this script with root or sudo."
fi

echo
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}            Sed build script - v${script_ver}"
echo -e "${GREEN}===============================================${NC}"
echo

# Set the C and C++ compilers
CC="gcc"
CXX="g++"
CFLAGS="-O3 -pipe -fno-plt -march=native"
CXXFLAGS="-O3 -pipe -fno-plt -march=native"
CPPFLAGS="-D_FORTIFY_SOURCE=2"
LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,${install_dir}/lib"
export CC CFLAGS CPPFLAGS CXX CXXFLAGS LDFLAGS

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
    echo -e "${GREEN}============================================${NC}"
    echo -e "  ${YELLOW}Do you want to clean up the build files?${NC}  "
    echo -e "${GREEN}============================================${NC}"
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choice (1 or 2): " choice

    case "$choice" in
        1) sudo rm -fr "$cwd";;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

# Install required apt packages
pkgs=(autoconf autoconf-archive autogen automake autopoint autotools-dev build-essential bzip2
      ccache curl git libaudit-dev libintl-perl libticonv-dev libtool libtool-bin lzip pkg-config
      valgrind zlib1g-dev librust-polling-dev)

missing_pkgs=""
for pkg in "${pkgs[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        missing_pkgs+=" $pkg"
    fi
done

if [[ -n "$missing_pkgs" ]]; then
    sudo apt-get install $missing_pkgs
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