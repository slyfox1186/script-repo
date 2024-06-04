#!/usr/bin/env bash
# shellcheck disable=SC2162,SC2317

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-yasm
##  Purpose: Build yasm
##  Updated: 08.31.23
##  Script version: 1.1

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set variables

script_ver=1.1
install_dir="/usr/local"
cwd="$PWD/yasm-build-script"
packages="$cwd/packages"
version=$(curl -fsS "https://yasm.tortall.net/releases/Release1.3.0.html" | grep -oP 'yasm-\K\d+\.\d+\.\d+' | sort -ruV | head -n1)
debug=OFF # Change THE DEBUG VARIABLE TO "ON" FOR HELP TROUBLESHOOTING ISSUES

echo
echo "yasm build script - v$script_ver"
echo "==============================================="
echo

# Create output directory
[[ ! -d "$cwd" ]] && mkdir -p "$packages"

# Set the c+cpp compilers
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
export CC CXX CFLAGS CXXFLAGS

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

# Create functions
exit_function() {
    echo
    echo "Make sure to star this repository to show your support!"
    echo "https://github.com/slyfox1186/script-repo"
    exit 0
}

fail() {
    echo "[ERROR] $1"
    echo
    echo "To report a bug please create an issue at:"
    echo "https://github.com/slyfox1186/script-repo/issues"
    echo
    exit 1
}

cleanup() {
    local choice

    echo
    echo "============================================"
    echo "  Do you want to clean up the build files?  "
    echo "============================================"
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choices are (1 or 2): " choice
    echo

    case "$choice" in
        1) sudo rm -fr "$cwd" "$0" ;;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

build() {
    echo
    echo "building $1 - version $2"
    echo "===================================="
    echo

    if [[ -f "$packages/$1.done" ]]; then
        if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        else
            echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $packages/$1.done lockfile."
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
            fail "Failed to execute: $*"
        fi
    else
        if ! output=$("$@" 2>&1); then
            notify-send 5000 "Failed to execute: $*"
            fail "Failed to execute: $*"
        fi
    fi
}

download() {
    dl_path="$packages"
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

    if [[ -f "${target_file}" ]]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"${dl_url}\" saving as \"$dl_file\""
        if ! curl -A "$user_agent" -Lso "${target_file}" "${dl_url}"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! curl -A "$user_agent" -Lso "${target_file}" "${dl_url}"; then
                fail "The script failed to download \"$dl_file\" twice and will now exit."
            fi
        fi
        echo "Download Completed"
    fi

    if [[ -d "$target_dir" ]]; then
        sudo rm -fr "$target_dir"
    fi

    mkdir -p "$target_dir"

    if [[ -n "$3" ]]; then
        if ! tar -xf "${target_file}" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "${target_file}"
            fail "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script."
        fi
    else
        if ! tar -xf "${target_file}" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "${target_file}"
            fail "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script."
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail "Unable to change the working directory to: $target_dir"
}

# Install required apt packages
pkgs=(
    autogen automake binutils bison build-essential bzip2 ccache cmake
    curl libc6-dev libintl-perl libpth-dev yasm yasm-bin lzip lzma-dev
    nasm ninja-build texinfo yasm yasm1g-dev
)

for pkg in ${pkgs[@]}; do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"

    [[ -z "$missing_pkg" ]] && missing_pkgs+="$pkg "
done

if [[ -n "$missing_pkgs" ]]; then
    sudo apt update
    sudo apt install $missing_pkgs
    clear
fi

build_done() { echo "$2" > "$packages/$1.done"; }

# Build program from source
if build "yasm" "$version"; then
    download "http://www.tortall.net/projects/yasm/releases/yasm-$version.tar.gz" "yasm-$version.tar.gz"
    execute autoreconf -fi
    execute cmake -B build -DCMAKE_INSTALL_DIR="$install_dir" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -G Ninja -Wno-dev
    execute ninja "-j$(nproc --all)" -C build
    execute sudo ninja -C build install
    build_done "yasm" "$version"
fi

# Prompt user to clean up files
cleanup

# Show exit message
exit_function
