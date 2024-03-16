#!/usr/bin/env bash

# GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-parallel
# Purpose: Build GNU parallel
# Updated: 03.16.24
# Script version: 2.1

set -e  # Exit on error

if [ "$EUID" -ne 0 ]; then
    echo
    echo "You must run this script with root/sudo."
    exit 1
fi

# SET THE VARIABLES
script_ver=2.0
archive_dir=parallel-latest
archive_url=https://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.$archive_ext"
cwd="$PWD/parallel-build-script"
install_dir=/usr/local
web_repo=https://github.com/slyfox1186/script-repo

echo "parallel build script - v$script_ver"
echo "==============================================="

# CREATE OUTPUT DIRECTORY
rm -fr "$cwd"
mkdir -p "$cwd"

# SET COMPILER FLAGS
CC=gcc
CXX=g++
CFLAGS="-g -O3 -pipe -march=native"
CXXFLAGS="-g -O3 -pipe -march=native"

# SET ENVIRONMENT VARIABLES
export PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"

export PKG_CONFIG_PATH="\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig:\
/lib64/pkgconfig:\
/lib/pkgconfig:\
/lib/x86_64-linux-gnu/pkgconfig\
"

# FUNCTIONS
exit_fn() {
    echo
    echo "\n%s\n\n%s\n\n"
    echo "Make sure to star this repository to show your support!"
    echo "$web_repo"
    echo
}

fail_fn() {
    echo
    echo "Error: $1"
    echo "To report a bug create an issue at: $web_repo/issues"
    echo
exit 1
}

cleanup_fn() {
    echo
    read -p "Do you want to clean up the build files? [y/N] " choice
    case "$choice" in
        y|Y ) rm -fr "$cwd" ;;
        * ) ;;
    esac
}

# INSTALL DEPENDENCIES
pkgs=(
    "autoconf" "autoconf-archive" "autogen" "automake" "binutils" "bison"
    "build-essential" "bzip2" "ccache" "curl" "libc6-dev" "libpth-dev"
    "libtool" "libtool-bin" "lzip" "lzma-dev" "m4" "nasm" "texinfo" "zlib1g-dev"
    "yasm"
)
apt install -y "${pkgs[@]}"

# DOWNLOAD SOURCE
curl -sSfLo "$cwd/$archive_name" "$archive_url"
mkdir -p "$cwd/$archive_dir/build"
tar -jxf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1

# BUILD
cd "$cwd/$archive_dir/build" || exit 1
../configure --prefix "$install_dir"
make "-j$(nproc --all)"
make install

# PROMPT CLEANUP
cleanup_fn

# EXIT MESSAGE
exit_fn
