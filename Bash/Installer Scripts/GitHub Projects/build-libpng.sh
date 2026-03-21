#!/usr/bin/env bash
# shellcheck disable=SC2162,SC2317

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-libpng.sh
##  Purpose: Build GNU libpng
##  Updated: 07.03.23
##  Script version: 1.2

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set variables
script_ver="1.2"
prog_name="libpng"
cwd="$PWD/libpng-build-script"
version=$(curl -fsS "https://github.com/pnggroup/libpng/tags/" | grep -oP '/tag/v\K\d+\.\d+\.\d+' | head -n1)
archive_name="$prog_name-$version"
install_dir="/usr/local/programs/$archive_name"
debug=OFF

echo "libpng build script - v${script_ver}"
echo "==============================================="
echo

# Create output directory

[[ -d "$cwd" ]] && sudo rm -fr "$cwd"
mkdir -p "$cwd"

# Set the c+cpp compilers
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

exit_function() {
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    echo
    exit 0
}

fail_fn() {
    echo "$1"
    echo "To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues"
    echo
    exit 1
}

cleanup_fn() {
    local choice

    echo "============================================"
    echo "  Do you want to clean up the build files?  "
    echo "============================================"
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choices are (1 or 2): " choice

    case "${choice}" in
        1)      sudo rm -fr "$cwd";;
        2)      echo;;
        *)
                unset choice
                echo
                cleanup_fn
                ;;
    esac
}

build() {
    echo "building $1 - version $2"
    echo "===================================="

    if [[ -f "$cwd/$1.done" ]]; then
        if grep -Fx "$2" "$cwd/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $cwd/$1.done lockfile to rebuild it."
            return 1
        elif ${latest}; then
            echo "$1 is oudebugtdated and will be rebuilt using version $2"
            return 0
        else
            echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $cwd/$1.done lockfile."
            return 1
        fi
    fi
    return 0
}

execute() {
    echo "$ $*"

    if [[ "${debug}" = "ON" ]]; then
        if ! output=$("$@"); then
            notify-send 5000 "Failed to execute: $*"
            fail_fn "Failed to execute: $*"
        fi
    else
        if ! output=$("$@" 2>&1); then
            notify-send 5000 "Failed to execute: $*"
            fail_fn "Failed to execute: $*"
        fi
    fi
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

    if [[ -f "$target_file" ]]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! curl -Lso "$target_file" "$dl_url"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! curl -Lso "$target_file" "$dl_url"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit:Line ${LINENO}"
            fi
        fi
        echo "Download Completed"
    fi

    [[ -d "$target_dir" ]] && sudo rm -fr "$target_dir"
    mkdir -p "$target_dir"

    if [[ -n "$3" ]]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script:Line ${LINENO}"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script:Line ${LINENO}"
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir:Line ${LINENO}"
}

# Install required apt packages

pkgs_fn() {
    pkgs=(asciidoc autogen automake binutils bison build-essential bzip2 ccache cmake
          curl libc6-dev libintl-perl libpth-dev libtool libtool-bin lzip lzma-dev
          nasm ninja-build texinfo xmlto yasm zlib1g-dev)

    for i in ${pkgs[@]}
    do
        missing_pkg="$(sudo dpkg -l | grep -q "$i")"
    
        if [[ -z "$missing_pkg" ]]; then
            missing_pkgs+=" $i"
        fi
    done
    
    if [[ -n "$missing_pkgs" ]]; then
        sudo apt install $missing_pkgs
        sudo apt -y autoremove
        clear
    fi
}

build_done() { echo "$2" > "$cwd/$1.done"; }

# Install apt packages

pkgs_fn

# Build program from source
if build "libpng" "$version"; then
    download "https://github.com/pnggroup/libpng/archive/refs/tags/v$version.tar.gz" "$archive_name.tar.gz"
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$install_dir" \
                         --disable-shared \
                         --enable-hardware-optimizations \
                         --enable-unversioned-links \
                         --with-binconfigs \
                         --with-pic \
                         --with-pkgconfigdir="$PKG_CONFIG_PATH" \
                         --with-zlib-prefix
    execute make "-j$(nproc --all)"
    execute sudo make install
    build_done "libpng" "$version"
fi

# Prompt user to clean up files
cleanup_fn

# Show exit message
exit_function
