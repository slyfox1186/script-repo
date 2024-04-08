#!/usr/bin/env bash

# Build GNU Bash
# Updated: 03.08.24
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-bash.sh

trap 'fail "Error occurred on line: $LINENO".' ERR

version=5.2.15
program_name=bash
install_prefix=/usr/local
build_dir="/tmp/$program_name-$version-build"
gnu_ftp="https://ftp.gnu.org/gnu/bash/"
verbose=0

GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

usage() {
    echo "Usage: ./build-bash.sh [OPTIONS]"
    echo "Options:"
    printf "  %-25s %s\n" "-p, --prefix DIR" "Set the installation prefix (default: $install_prefix)"
    printf "  %-25s %s\n" "-v, --verbose" "Enable verbose logging"
    printf "  %-25s %s\n" "-h, --help" "Show this help message"
    exit 0
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -p|--prefix)
                install_prefix="$2"
                shift 2
                ;;
            -v|--verbose)
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
        printf "${GREEN}%s${RESET}\n" "$1"
    fi
}

fail() {
    printf "${RED}%s${RESET}\n" "$1"
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

install_deps() {
    log_msg "Checking and installing missing packages..."
    local pkgs=(autoconf automake binutils gcc make curl tar lzip libticonv-dev gettext libpth-dev)
    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y --no-install-recommends "${pkgs[@]}"
    elif command -v dnf &>/dev/null; then
        dnf install -y "${pkgs[@]}"
    elif command -v zypper &>/dev/null; then
        zypper install -y "${pkgs[@]}"
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm --needed "${pkgs[@]}"
    else
        fail "Unsupported package manager. Please install the required dependencies manually."
    fi
}

find_latest_release() {
    log_msg "Finding the latest release..."
    local latest_tarball=$(curl -fsS "$gnu_ftp" | grep 'bash-[0-9].*\.tar\.gz' | grep -v ".sig" | sed -n 's/.*href="\([^"]*\).*/\1/p' | sort -rV | head -n1)
    if [[ -z $latest_tarball ]]; then
        fail "Failed to find the latest release."
    fi
    archive_url="${gnu_ftp}${latest_tarball}"
    archive_name="${latest_tarball}"
    program_version=$(echo "$latest_tarball" | sed -n 's/bash-\([0-9.]*\)\.tar\.gz/\1/p')
}

download_archive() {
    log_msg "Downloading archive..."
    if [[ ! -f "$build_dir/$archive_name" ]]; then
        curl -fsSLo "$build_dir/$archive_name" "$archive_url"
    fi
}

extract_archive() {
    log_msg "Extracting archive..."
    tar -xzf "$build_dir/$archive_name" -C "$build_dir" --strip-components 1
}

set_env_vars() {
    log_msg "Setting environment variables..."
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-O3 -pipe -fno-plt -march=native"
    CXXFLAGS="-O3 -pipe -fno-plt -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_prefix/$program_name-$program_version/lib"
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/lib64/pkgconfig:/lib/pkgconfig"
    export CC CFLAGS CXX CXXFLAGS CPPFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

configure_build() {
    log_msg "Configuring build..."
    cd "$build_dir"
    autoreconf -fi
    mkdir -p build && cd build
    ../configure --prefix="$install_prefix/$program_name-$program_version" \
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
    make install
}

create_symlinks() {
    log_msg "Creating symlinks..."
    for file in "$install_prefix/$program_name-$program_version"/bin/*; do
        ln -sfn "$file" "$install_prefix/bin/$(basename "$file" | sed 's/^\w*-//')"
    done
}

cleanup() {
    log_msg "Cleaning up..."
    echo
    read -rp "Remove temporary build directory '$build_dir'? [y/N] " response
    if [[ $response =~ ^[Yy]$ ]]; then
        rm -rf "$build_dir"
    fi
}

main() {
    parse_args "$@"

    if [[ "$EUID" -ne 0 ]]; then
        fail "This script must be run as root or with sudo."
    fi

    [[ -d "$build_dir" ]] && rm -rf "$build_dir"
    mkdir -p "$build_dir"

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

    log_msg "Build completed successfully."
    log_msg "Make sure to star this repository to show your support!"
    log_msg "https://github.com/slyfox1186/script-repo"
}

main "$@"
