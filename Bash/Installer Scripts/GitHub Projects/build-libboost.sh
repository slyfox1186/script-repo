#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-boost.sh
##  Purpose: build libboost
##  Updated: 09.13.23
##  Script version: 1.0

if [ "$EUID" -eq 0 ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables

script_ver=1.0
archive_dir=b2-git
archive_url=https://github.com/bfgroup/b2.git
cwd="$PWD"/boost-build-script
install_dir=/usr/local
user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
web_repo=https://github.com/slyfox1186/script-repo

printf "%s\n%s\n\n" \
    "libboost build script - v${script_ver}" \
    '==============================================='

# Create output directory

[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
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
export CC CXX CFLAGS CXXFLAGS PATH PKG_CONFIG_PATH

# Create functions

exit_function()
{
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

fail_fn()
{
    printf "\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug create an issue at: $web_repo/issues"
    exit 1
}

cleanup_fn()
{
    local choice

    printf "%s\n%s\n%s\n\n%s\n%s\n\n" \
        '============================================' \
        '  Do you want to clean up the build files?  ' \
        '============================================' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice

    case "${choice}" in
        1)      sudo rm -fr "$cwd";;
        2)      echo;;
        *)
                clear
                printf "%s\n\n" 'Bad user input. Reverting script...'
                sleep 3
                unset choice
                clear
                cleanup_fn
                ;;
    esac
}

# Install required apt packages

pkgs=(autoconf autoconf-archive autogen automake binutils build-essential ccache clang cmake
      curl git libclang-dev libtool libtool-bin llvm-dev lzip m4 nasm pkg-config zlib1g-dev yasm)


for i in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "${i}")"

    if [ -z "${missing_pkg}" ]; then
        missing_pkgs+=" ${i}"
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
    sudo apt -y autoremove
    clear
fi

# Download the archive file

if [ -d "$cwd/$archive_dir" ]; then
    sudo rm -fr "$cwd/$archive_dir"
fi

git clone "${archive_url}" "$cwd/$archive_dir"
mkdir -p "$cwd/$archive_dir/build"

# Build program from source

clear

cd "$cwd/$archive_dir" || exit 1
./bootstrap.sh
if ! sudo ./b2 install --prefix="$install_dir"; then
    fail_fn "Failed to execute: ./b2 install --prefix=$install_dir:Line ${LINENO}"
    exit 1
fi

# Prompt user to clean up files
cleanup_fn

# Show exit message
exit_function
