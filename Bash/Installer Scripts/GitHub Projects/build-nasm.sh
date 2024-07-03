#!/usr/bin/env bash
# Shellcheck disable=sc2162,sc2317

# Github: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-nasm.sh
# Purpose: Build NASM
# Updated: 07.03.24
# Script version: 1.3

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set global variables
script_ver="1.3"
cwd="$PWD/nasm-build-script"
install_dir="/usr/local/programs/nasm"
debug=OFF

# Create output directories
mkdir -p "$cwd"

# Figure out which compilers to use
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
export CC CXX CFLAGS CXXFLAGS

# Set the available cpu count for parallel processing (speeds up the build process)
if [ -f /proc/cpuinfo ]; then
    cpu_threads="$(grep -c ^processor /proc/cpuinfo)"
else
    cpu_threads="$(nproc --all)"
fi

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PATH PKG_CONFIG_PATH

# Create functions
exit_function() {
    echo
    echo "The script has completed"
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail() {
    printf "\n\n%s\n\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug please visit: " \
        "https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

cleanup() {
    sudo rm -fr "$cwd"
}

execute() {
    echo "$ $*"

    if [[ "$debug" = "ON" ]]; then
        if ! output="$("$@")"; then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail "Failed to execute: $*"
        fi
    else
        if ! output="$("$@" 2>&1)"; then
            notify-send -t 5000 "Failed to execute: $*" 2>/dev/null
            fail "Failed to execute: $*"
        fi
    fi
}

build() {
    echo "Building $1 - version $2"
    echo "=========================================="
    echo

    if [ -f "$cwd/$1.done" ]; then
        if grep -Fx "$2" "$cwd/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $cwd/$1.done lockfile to rebuild it."
            return 1
        fi
    fi
    return 0
}

build_done() {
    echo "$2" > "$cwd/$1.done"
}

download() {
    dl_path="$cwd"
    dl_url="$1"
    dl_file="${2:-"${1##*/}"}"

    if [[ "$dl_file" =~ tar. ]]; then
        output_dir="${dl_file%.*}"
        output_dir="${3:-"${output_dir%.*}"}"
    else
        output_dir="${3:-"${dl_file%.*}"}"
    fi

    target_file="$dl_path/$dl_file"
    target_dir="$dl_path/$output_dir"

    if [ -f "$target_file" ]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! wget --show-progress -t 2 -cqO "$target_file" "$dl_url"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! wget --show-progress -t 2 -cqO "$target_file" "$dl_url"; then
                fail "The script failed to download \"$dl_file\" twice and will now exit. Line: $LINENO"
            fi
        fi
        printf "\n%s\n\n" "Download completed"
    fi

    [[ -d "$target_dir" ]] && sudo rm -fr "$target_dir"
    mkdir -p "$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>&1; then
            sudo rm "$target_file"
            fail "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>&1; then
            sudo rm "$target_file"
            fail "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: $LINENO"
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail "Unable to change the working directory to: $target_dir. Line: $LINENO"
}

find_latest_nasm_version() {
    version=$(
              curl -fsS "https://www.nasm.us/pub/nasm/stable/" |
              grep -oP 'nasm-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.xz)' |
              sort -ruV | head -n1
         )
}

# Print the options available when manually running the script
pkgs=(
      autoconf automake autopoint binutils binutils-dev bison
      build-essential ccache curl jq libc6 libc6-dev libedit-dev
      libtool libxml2-dev m4 nasm ninja-build yasm zlib1g-dev
)

for pkg in ${pkgs[@]}; do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"

    if [[ -z "$missing_pkg" ]]; then
        missing_pkgs+=" $pkg"
    fi
done

if [[ -n "$missing_pkgs" ]]; then
    sudo apt update
    sudo apt install $missing_pkgs
    clear
else
    printf "%s\n" "The APT packages are already installed"
fi

# Begin building clang
clear
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner "nasm build script - version $script_ver"

find_latest_nasm_version
if build "nasm" "$version"; then
    download "https://www.nasm.us/pub/nasm/stable/nasm-$version.tar.xz"
    execute ./autogen.sh
    execute ./configure --prefix="$install_dir" --enable-ccache
    execute make "-j$cpu_threads"
    execute sudo make install
fi

# Prompt the user to clean up the build files
cleanup

# Show exit message
exit_function
