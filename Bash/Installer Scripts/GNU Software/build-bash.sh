#!/usr/bin/env bash

# Build GNU Bash
# Updated: 03.08.24
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-bash.sh

set -o pipefail

version=5.2.15
program_name=bash
install_dir="/usr/local/${program_name}-${version}"
build_dir="${PWD}/${program_name}-${version}-build-script"
workspace="$build_dir/workspace"
gnu_ftp="https://ftp.gnu.org/gnu/bash/"
verbose=0

GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Build and install GNU Bash from source."
    echo
    echo "Options:"
    printf "  %-25s %s\n" "-v VERSION, --version VERSION" "Set the version of Bash to build (default: ${version})"
    printf "  %-25s %s\n" "-V, --verbose" "Enable verbose logging"
    printf "  %-25s %s\n" "-h, --help" "Show this help message"
    echo
    echo "Example:"
    echo "$0 -v 5.2.15"
    exit 0
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -v|--version)
                version="$2"
                shift 2
                ;;
            -V|--verbose)
                verbose=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)  fail "Unknown option: $1. Use -h or --help for usage information." ;;
        esac
    done
}

log_msg() {
    if [[ "$verbose" -eq 1 ]]; then
        printf "${GREEN}[INFO] %s${RESET}\n" "$1"
    fi
}

fail() {
    printf "${RED}[ERROR] %s${RESET}\n" "$1" >&2
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues" >&2
    exit 1
}

install_deps() {
    log_msg "Checking and installing missing packages..."
    local pkgs=(autoconf automake binutils gcc make curl tar lzip libticonv-dev gettext libpth-dev)
    if command -v sudo &>/dev/null; then
        if command -v apt &>/dev/null; then
            sudo apt update
            sudo apt install -y --no-install-recommends "${pkgs[@]}"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "${pkgs[@]}"
        elif command -v zypper &>/dev/null; then
            sudo zypper install -y "${pkgs[@]}"
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm --needed "${pkgs[@]}"
        else
            fail "Unsupported package manager. Please install the required dependencies manually."
        fi
    else
        fail "sudo is required to install dependencies. Please install sudo or run the script with root privileges."
    fi
}

find_latest_release() {
    log_msg "Finding the latest release..."
    local latest_tarball
    latest_tarball=$(curl -fsS "$gnu_ftp" | grep -oP "bash-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz" | sort -rV | head -n1)
    if [[ -z "$latest_tarball" ]]; then
        fail "Failed to find the specified release: ${version}."
    fi
    archive_url="${gnu_ftp}${latest_tarball}"
    archive_name="${latest_tarball}"
}

download_archive() {
    log_msg "Downloading archive..."
    if [[ ! -f "${build_dir}/${archive_name}" ]]; then
        curl -LSso "${build_dir}/${archive_name}" "$archive_url"
    fi
}

extract_archive() {
    log_msg "Extracting archive..."
    tar -zxf "${build_dir}/${archive_name}" -C "$workspace" --strip-components 1
}

set_env_vars() {
    log_msg "Setting environment variables..."
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-O2 -pipe -fno-plt -march=native -mtune=native -D_FORTIFY_SOURCE=2"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,${install_dir}/lib"
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/lib64/pkgconfig:/lib/pkgconfig"
    export CC CFLAGS CXX CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

configure_build() {
    log_msg "Configuring build..."
    cd "$workspace"
    autoreconf -fi
    mkdir -p build && cd build
    ../configure --prefix="$install_dir" \
                 --disable-nls \
                 --disable-profiling \
                 --enable-brace-expansion \
                 --enable-history \
                 --enable-separate-helpfiles \
                 --enable-threads=posix \
                 --with-bash-malloc \
                 --with-libiconv-prefix=/usr \
                 --with-libintl-prefix=/usr \
                 --with-libpth-prefix=/usr \
                 --without-included-gettext
}

compile_build() {
    log_msg "Compiling..."
    make "-j$(nproc --all)"
}

install_build() {
    log_msg "Installing..."
    if command -v sudo &>/dev/null; then
        sudo make install
    else
        fail "sudo is required to install the program. Please install sudo or run the script with root privileges."
    fi
}

create_symlinks() {
    log_msg "Creating symlinks..."
    for dir in "${install_dir}"/{bin,include,lib,lib/pkgconfig,share}; do
        for file in "${install_dir}/${dir}"/*; do
            if [[ -e $file ]]; then
                sudo ln -sfn "$file" "/usr/local/${dir}/${file##*/}"
            fi
        done
    done
}

cleanup() {
    log_msg "Cleaning up..."
    echo
    read -rp "Remove temporary build directory '${build_dir}'? [y/N] " response
    if [[ $response =~ ^[Yy]$ ]]; then
        sudo rm -rf "$build_dir"
    fi
}

main() {
    parse_args "$@"

    mkdir -p "$workspace/build"

    install_deps
    find_latest_release
    download_archive
    extract_archive
    set_env_vars
    configure_build
    compile_build
    install_build
    create_symlinks
    cleanup

    echo
    log_msg "Build completed successfully."
    log_msg "Make sure to star this repository to show your support!"
    log_msg "https://github.com/slyfox1186/script-repo"
}

main "$@"
