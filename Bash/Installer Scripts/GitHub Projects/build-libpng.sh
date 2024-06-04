#!/usr/bin/env bash
# shellcheck disable=SC2162,SC2317

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-libpng.sh
##  Purpose: Build GNU libpng
##  Updated: 08.31.23
##  Script version: 1.1

if [ "${EUID}" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Set variables
script_ver=1.1
cwd="$PWD"/libpng-build-script
install_dir=/usr/local
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
web_repo=https://github.com/slyfox1186/script-repo
debug=OFF

printf "\n%s\n%s\n\n" \
    "libpng build script - v${script_ver}" \
    '==============================================='

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
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug create an issue at: $web_repo/issues"
    exit 1
}

cleanup_fn() {
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

build() {
    printf "\n%s\n%s\n" \
        "building $1 - version $2" \
        '===================================='

    if [ -f "$cwd/$1.done" ]; then
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
    echo "$ ${*}"

    if [ "${debug}" = 'ON' ]; then
        if ! output=$("$@"); then
            notify-send 5000 "Failed to execute: ${*}"
            fail_fn "Failed to execute: ${*}"
        fi
    else
        if ! output=$("$@" 2>&1); then
            notify-send 5000 "Failed to execute: ${*}"
            fail_fn "Failed to execute: ${*}"
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

    if [ -f "${target_file}" ]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"${dl_url}\" saving as \"$dl_file\""
        if ! curl -A "$user_agent" -Lso "${target_file}" "${dl_url}"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! curl -A "$user_agent" -Lso "${target_file}" "${dl_url}"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit:Line ${LINENO}"
            fi
        fi
        echo 'Download Completed'
    fi

    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    fi

    mkdir -p "$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "${target_file}" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "${target_file}"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script:Line ${LINENO}"
        fi
    else
        if ! tar -xf "${target_file}" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "${target_file}"
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

build_done() { echo "$2" > "$cwd/$1.done"; }

# Install apt packages

pkgs_fn

# Build program from source
if build "libpng" "1.6.40"; then
    download "https://github.com/glennrp/libpng/archive/refs/tags/v1.6.40.tar.gz" "libpng-1.6.40.tar.gz"
    execute autoupdate
    execute autoreconf -fi
    execute ./configure --prefix="$install_dir" \
                         --{build,host}=x86_64-linux-gnu \
                         --disable-shared \
                         --enable-hardware-optimizations \
                         --enable-unversioned-links \
                         --with-binconfigs \
                         --with-pic \
                         --with-pkgconfigdir="${PKG_CONFIG_PATH}" \
                         --with-zlib-prefix
    execute make "-j$(nproc --all)"
    execute sudo make install-header-links
    execute sudo make install-library-links
    execute sudo make install
    execute make distclean
    build_done "libpng" "1.6.40"
fi

# Prompt user to clean up files
cleanup_fn

# Show exit message
exit_function
