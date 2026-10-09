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

##  Github script: https://github.com/slyfox1186/script-repo/edit/main/Bash/installer-scripts/gnu-software/build-dbus
##  Purpose: build gnu dbus
##  Updated: 11.06.23
##  Script version: 1.2

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables
script_ver=1.2
archive_dir=dbus-1.15.8
archive_url="https://dbus.freedesktop.org/releases/dbus/$archive_dir.tar.xz"
archive_ext="${archive_url//*./}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/dbus-build-script"
install_dir="/usr/local/programs/$archive_dir"

echo "dbus build script version $script_ver"
echo "==============================================="
echo

# Create output directory

cwd=$(gnu_new_workdir)

mkdir -p "$cwd"

# Set the c + cpp compilers
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export CC CFLAGS CXX CXXFLAGS PKG_CONFIG_PATH PATH

# Create functions
exit_fn() {
    echo
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail() {
    echo
    echo "$1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
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

# Install required apt packages
pkgs=(apparmor apparmor-utils autoconf autoconf-archive autogen automake autopoint autotools-dev
      build-essential bzip2 ccache curl git libapparmor-dev libaudit-dev libglib2.0-dev libintl-perl
      librust-polling-dev libsystemd-dev libtool libtool-bin libx11-dev lzip pkg-config valgrind
      zlib1g-dev)

missing_pkgs=()

for pkg in "${pkgs[@]}"
do
    missing_pkg="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -o 'ok installed' || true)"

    if [[ -z "$missing_pkg" ]]; then
        missing_pkgs+=("$pkg")
    fi
done

if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
    sudo apt install "${missing_pkgs[@]}"
fi

# Download the archive file
if [[ ! -f "$cwd/$archive_name" ]]; then
    gnu_curl -Lso "$cwd/$archive_name" "$archive_url"
fi

# Create output directory
if [[ -d "$cwd/$archive_dir" ]]; then
    sudo rm -fr "$cwd/$archive_dir"
fi
mkdir -p "$cwd/$archive_dir/build"

# Extract archive files
if ! tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    fail "Failed to extract: $cwd/$archive_name"
fi

# Build program from source
cd "$cwd/$archive_dir" || exit 1
cd build || exit 1
../configure --prefix="$install_dir" \
             --enable-apparmor \
             --enable-code-coverage \
             --enable-epoll \
             --enable-inotify \
             --enable-qt-help=auto \
             --enable-selinux \
             --enable-systemd \
             --enable-tests \
             --enable-user-session \
             --enable-x11-autolaunch \
             --with-pic \
             --with-valgrind \
             PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
if ! make "-j$gnu_jobs"; then
    fail "Failed to execute: make -j$gnu_jobs. Line: $LINENO"
fi

if ! sudo make install; then
    fail "Failed to execute: sudo make install. Line: $LINENO"
fi

# Prompt user to clean up files
cleanup

# Show exit message
exit_fn
