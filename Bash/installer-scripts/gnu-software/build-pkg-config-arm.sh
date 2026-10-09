#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Ee -o pipefail
trap 'printf "Build failed at line %s. Build files were retained for inspection.\n" "$LINENO" >&2; exit 1' ERR

gnu_curl() {
    command curl -q --fail --location --show-error --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 600 --proto '=https' --proto-redir '=https' \
        --user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$@"
}

gnu_new_workdir() {
    local base="${TMPDIR:-/tmp}"
    [[ "$base" == /* && -d "$base" ]] || { printf 'TMPDIR must be an existing absolute directory.\n' >&2; return 1; }
    mktemp -d -- "$base/${0##*/}.XXXXXX"
}

gnu_jobs="${JOBS:-$(nproc)}"
[[ "$gnu_jobs" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer.\n' >&2; exit 1; }

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/installer-scripts/gnu-software/build-pkg-config.sh
##  Purpose: build gnu pkg-config
##  Updated: 09.19.24
##  Script version: 1.3

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set variables
script_ver=1.3
archive_dir="pkg-config-0.29.2"
archive_url="https://pkgconfig.freedesktop.org/releases/$archive_dir.tar.gz"
archive_name="${archive_dir}.tar.${archive_url##*.}"
cwd="$PWD/pkg-config-build-script"
install_dir="/usr/local/programs/$archive_dir"

# Create logging functions
log() {
    echo -e "${GREEN}[INFO] Bash:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING] Bash:${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR] Bash:${NC} $1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Check if running as root or with sudo
if [[ "$EUID" -eq 0 ]]; then
    fail "You must run this script without root or sudo."
fi

log "pkg-config build script version $script_ver"
echo "==============================================="
echo

# Set the c + cpp compilers
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
export CC CFLAGS CXX CXXFLAGS

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

# Create functions
exit_fn() {
    log "Make sure to star this repository to show your support!"
    log "https://github.com/slyfox1186/script-repo"
    exit 0
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

# Install required apt packages
pkgs=(autoconf autoconf-archive autogen automake build-essential ca-certificates ccache clang curl \
      libaria2-0 libaria2-0-dev libc-ares-dev libdmalloc-dev libgcrypt20-dev libgmp-dev libgnutls28-dev \
      libgpg-error-dev libjemalloc-dev libmbedtls-dev libnghttp2-dev librust-openssl-dev libsqlite3-dev \
      libssh2-1-dev libssh-dev libssl-dev libxml2-dev pkg-config zlib1g-dev)

missing_pkgs=()
for pkg in "${pkgs[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        missing_pkgs+=("$pkg")
    fi
done

if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
    sudo apt-get install "${missing_pkgs[@]}"
fi

# Download the archive file
cwd=$(gnu_new_workdir)
if [[ ! -f "$cwd/$archive_name" ]]; then
    gnu_curl -Lso "$cwd/$archive_name" "$archive_url"
fi

# Create output directory

mkdir -p "$cwd/$archive_dir/build"

# Extract archive files
if ! tar -zxf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    fail "Failed to extract: $cwd/$archive_name"
fi

# Build program from source
cd "$cwd/$archive_dir/build" || fail "Failed to change directory to: $cwd/$archive_dir/build"
../configure --prefix="$install_dir" \
             --enable-indirect-deps \
             --with-internal-glib \
             --with-pc-path="$PKG_CONFIG_PATH" \
             --with-pic
make "-j$gnu_jobs"
if ! sudo make install; then
    fail "Failed to execute: sudo make install. Line: ${LINENO}"
fi

# Create soft links
sudo ln -sf "$install_dir/bin/pkg-config" "/usr/local/bin/pkg-config"

# Prompt user to clean up files
cleanup

# Show exit message
exit_fn
