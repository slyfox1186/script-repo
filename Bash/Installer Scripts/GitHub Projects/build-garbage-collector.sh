#!/usr/bin/env bash

###########################################################################################################
##
##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-garbage-collector
##
##  Purpose: Build Boehm-Demers-Weiser Conservative Garbage Collector
##
##  Updated: 08.16.23
##
##  Script version: 1.0
##
###########################################################################################################

clear

if [ "${EUID}" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set variables

script_ver=1.0
archive_dir=gc-8.2.4
archive_url=https://github.com/ivmai/bdwgc/releases/download/v8.2.4/gc-8.2.4.tar.gz
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.${archive_ext}"
cwd="$PWD/garbage-collector-build-script"
web_repo=https://github.com/slyfox1186/script-repo

printf "\n%s\n%s\n\n" \
    "garbage collector build script - v${script_ver}" \
    '==============================================='

# Create output directory
[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

# Set the c+cpp compilers
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -mtune=native"
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

pkgs_fn()
{
    pkgs=(autoconf autoconf-archive autogen automake binutils bison build-essential bzip2 ccache curl
          libc6-dev libintl-perl libpth-dev libticonv-dev libtool libtool-bin lzip lzma-dev m4 nasm texinfo
          zlib1g-dev yasm)

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
}

# Download the archive file

if [ ! -f "$cwd/${archive_name}" ]; then
    curl -Lso "$cwd/${archive_name}" "${archive_url}"
fi

# Create output directory

if [ -d "$cwd/$archive_dir" ]; then
    sudo rm -fr "$cwd/$archive_dir"
fi
mkdir -p "$cwd/$archive_dir/build"

# Extract archive files

if ! tar -zxf "$cwd/${archive_name}" -C "$cwd/$archive_dir" --strip-components 1; then
    printf "%s\n\n" "Failed to extract: $cwd/${archive_name}"
    exit 1
fi

# Build program from source

cd "$cwd/$archive_dir" || exit 1
autoreconf -fi
cd build || exit 1
../configure --prefix=/usr/local             \
             --{build,host}=x86_64-linux-gnu \
             --disable-nls                   \
             --disable-werror                \
             --enable-cplusplus              \
             --enable-gc-assertions          \
             --enable-gcov                   \
             --enable-large-config           \
             --enable-static                 \
             --with-libatomic-ops=check      \
             --with-libiconv-prefix=/usr     \
             --with-libintl-prefix=/usr      \
             --with-libpth-prefix=/usr       \
             --with-pic
make "-j$(nproc --all)"
if ! sudo make install; then
    fail_fn "Failed to execute: sudo make install:Line ${LINENO}"
    exit 1
fi

# Prompt user to clean up files
cleanup_fn

# Show exit message
exit_function
