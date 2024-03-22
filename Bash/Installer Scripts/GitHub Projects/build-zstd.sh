#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-zstd
##  Purpose: Build zstd compression software
##  Features: Static and shared build
##  Changed: Static build to both
##  Updated: 12.03.23
##  Script version: 1.2

clear

if [ "$EUID" -eq 0 ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set the variables

script_ver=1.2
archive_ver=1.5.5
archive_dir="zstd-$archive_ver"
archive_url="https://github.com/facebook/zstd/releases/download/v$archive_ver/$archive_dir.tar.gz"
archive_ext="${archive_url//*.}"
archive_name="$archive_dir.tar.${archive_ext}"
install_dir=/usr/local
cwd="$PWD/zstd-build-script"

printf "%s\n%s\n\n" \
    "ZStd Build Script - v$script_ver" \
    '==============================================='
sleep 2

# Create output directory

if [ -d "$cwd" ]; then
    sudo rm -fr "$cwd"
fi
mkdir -p "$cwd"

# Set the c+cpp compilers

export CC=gcc CXX=g++

# Export compiler optimization flags

export {CFLAGS,CXXFLAGS}='-g -O3 -pipe -fno-plt -march=native'

# Set the path variable

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
/usr/bin:\
/sbin:\
/bin:\
/usr/local/games:\
/usr/games:\
/snap/bin\
"
export PATH

# Set the pkg_config_path variable

PKG_CONFIG_PATH="\
/usr/share/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/lib/pkgconfig\
"
export PKG_CONFIG_PATH

# Create functions

exit_fn()
{
    printf "\n%s\n\n%s\n%s\n\n" \
        'The script has completed' \
        'Make sure to star this repository to show your support!' \
        "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail_fn()
{
    printf "\n\n%s\n\n%s\n\n%s\n\n" \
        "$1" \
        'Please create a support ticket so I can work on a fix.' \
        "https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

cleanup_fn()
{
    local choice

    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to remove the build files?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice
    clear

    case "${choice}" in
        1)      sudo rm -fr "$cwd" "${0}";;
        2)      return 0;;
        *)
                unset choice
                cleanup_fn
                ;;
    esac
}

# Install required apt packages

pkgs=(autoconf autogen automake build-essential ccache clang cmake curl git libdmalloc-dev
      libjemalloc-dev liblz4-dev liblzma-dev libtool libtool-bin m4 meson ninja-build
      pkg-config zlib1g-dev)

for pkg in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"

    if [ -z "$missing_pkg" ]; then
        missing_pkgs+="$pkg "
    fi
done

if [ -n "$missing_pkgs" ]; then
    sudo apt install $missing_pkgs
    sudo apt -y autoremove
    clear
fi

# Download the archive file

if [ ! -f "$cwd/$archive_name" ]; then
    wget --show-progress -cqO "$cwd/$archive_name" "$archive_url"
fi

# Create the output directory

if [ -d "$cwd/$archive_dir" ]; then
    sudo rm -fr "$cwd/$archive_dir"
fi
mkdir -p "$cwd/$archive_dir"

# Extract the archive file

if ! tar -zxf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
    fail_fn "Failed to extract: $cwd/$archive_name"
fi

# Build the program from source code

cd "$cwd/$archive_dir/build/meson" || exit 1
meson setup build --prefix="$install_dir" \
                  --buildtype=release \
                  --default-library=both \
                  --strip \
                  -Dbin_tests=false
echo
if ! ninja "-j$(nproc --all)" -C build; then
    fail_fn "Failed to execute: ninja -j$(nproc --all) -C build install. Line: $LINENO"
fi
echo
if ! sudo ninja -C build install; then
    fail_fn "Failed to execute: sudo ninja -C build install. Line: $LINENO"
fi

if [[ ! -f "/usr/lib/x86_64-linux-gnu/libzstd.so.1.5.5" ]]; then
    sudo cp -f "$install_dir/lib/x86_64-linux-gnu/libzstd.so.1.5.5" "/usr/lib/x86_64-linux-gnu/libzstd.so.1.5.5"
    sudo ln -sf "/usr/lib/x86_64-linux-gnu/libzstd.so.1.5.5" "/usr/lib/x86_64-linux-gnu/libzstd.so.1"
fi

[[ -f "/usr/local/lib/x86_64-linux-gnu/libzstd.so.1" ]] && sudo rm "/usr/local/lib/x86_64-linux-gnu/libzstd.so.1"
[[ -f "/usr/local/lib/x86_64-linux-gnu/libzstd.so" ]] && sudo rm "/usr/local/lib/x86_64-linux-gnu/libzstd.so"

# Prompt user to clean up files
cleanup_fn

# Show exit message
exit_fn
