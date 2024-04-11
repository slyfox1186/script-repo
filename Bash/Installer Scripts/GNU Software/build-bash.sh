#!/usr/bin/env bash

# Build GNU Bash
# Updated: 04.11.24
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-bash.sh
# Script Version: 2.0

trap 'fail "Error occurred on line: $LINENO".' ERR

version="5.2.15"
program_name="bash"
install_dir="/usr/local"
build_dir="/tmp/$program_name-$version-build"
workspace="$build_dir/workspace"
gnu_ftp="https://ftp.gnu.org/gnu/bash/"
verbose=0

GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

usage() {
    echo "Usage: ./build-bash.sh [OPTIONS]"
    echo "Options:"
    printf "  %-25s %s\n" "-p, --prefix DIR" "Set the installation prefix (default: $install_dir)"
    printf "  %-25s %s\n" "-v, --verbose" "Enable verbose logging"
    printf "  %-25s %s\n" "-h, --help" "Show this help message"
    exit 0
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -p|--prefix)
                install_dir="$2"
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

log() {
    if [[ "$verbose" -eq 1 ]]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

fail() {
    printf "${RED}[ERROR]${NC} $1"
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

install_deps() {
    log "Checking and installing missing packages..."
    local apt_pkgs arch_pkgs
    apt_pkgs=(
            autoconf autoconf-archive binutils build-essential ccache
            curl gettext libpth-dev libticonv-dev libtool lzip m4 tar
        )
    arch_pkgs=(
            autoconf autoconf-archive binutils base-devel ccache
            curl gettext npth libiconv libtool lzip m4 tar
        )
    if command -v apt &>/dev/null; then
        sudo apt update
        sudo apt -y install "${apt_pkgs[@]}"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${apt_pkgs[@]}"
    elif command -v zypper &>/dev/null; then
        sudo zypper install -y "${apt_pkgs[@]}"
    elif command -v pacman &>/dev/null; then
        sudo pacman -Syu
        sudo pacman -Sy --needed --noconfirm "${arch_pkgs[@]}"
    else
        fail "Unsupported package manager. Please install the required dependencies manually."
    fi
}

find_latest_release() {
    log "Finding the latest release..."
    local tarball=$(curl -fsS "$gnu_ftp" | grep -oP 'bash-[0-9\.]*\.tar\.gz' | sort -rV | head -n1)
    if [[ -z "$tarball" ]]; then
        fail "Failed to find the latest release."
    fi
    archive_url="${gnu_ftp}${tarball}"
    archive_name="${tarball}"
    version=$(echo "$tarball" | grep -oP 'bash-[0-9.]{5,6}')
}

download_archive() {
    log "Downloading archive..."
    if [[ ! -f "$build_dir/$archive_name" ]]; then
        curl -LSso "$build_dir/$archive_name" "$archive_url"
    fi
}

extract_archive() {
    echo
    log "Extracting archive..."
    tar -zxf "$build_dir/$archive_name" -C "$workspace" --strip-components 1
}

set_env_vars() {
    echo
    log "Setting environment variables..."
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-O2 -pipe -fno-plt -march=native -mtune=native -D_FORTIFY_SOURCE=2"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/$program_name-$version/lib"
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/lib64/pkgconfig:/lib/pkgconfig"
    export CC CFLAGS CXX CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

configure_build() {
    echo
    log "Configuring build..."
    cd "$workspace" || exit 1
    autoreconf -fi
    cd build || exit 1
    echo
    log "Configuring..."
    ../configure --prefix="$install_dir/$program_name-$version" \
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
    echo
    log "Compiling..."
    make "-j$(nproc --all)"
}

install_build() {
    echo
    log "Installing..."
    sudo make install
}

create_symlinks() {
    echo
    log "Creating symlinks..."
    for file in "$install_dir/$program_name-$version"/bin/*; do
        sudo ln -sfn "$file" "$install_dir/bin/$(basename "$file" | sed 's/^\w*-//')"
    done
}

# Cleanup resources  
cleanup() {
    echo
    read -p "Remove temporary build directory '$build_dir'? [y/N] " response
    case "$response" in
        [yY]*|"")
        sudo rm -rf "$build_dir"
        log_msg "Build directory removed."
        ;;
        [nN]*) ;;
    esac
}

main() {
    parse_args "$@"

    if [[ "$EUID" -eq 0 ]]; then
        fail "This script must be without run root or with sudo."
    fi

    [[ -d "$workspace" ]] && sudo rm -rf "$workspace"
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
    log "Build completed successfully."
    echo
    log "Make sure to star this repository to show your support!"
    log "https://github.com/slyfox1186/script-repo"
}

main "$@"
