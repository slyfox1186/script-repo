#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/grep/Installer%20Scripts/GNU%20Software/build-grep.sh
##  Purpose: build gnu grep
##  Updated: 04.11.24
##  Script version: 2.1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

trap 'fail "Error occurred on line: $LINENO".' ERR

version="3.11"
program_name="grep"
install_dir="/usr/local"
build_dir="/tmp/$program_name-$version-build"
workspace="$build_dir/workspace"
gnu_ftp="https://ftp.gnu.org/gnu/grep/"
verbose=0

GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

usage() {
    echo "Usage: ./build-grep.sh [OPTIONS]"
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

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

install_deps() {
    log "Checking and installing missing packages..."
    local apt_pkgs arch_pkgs
    apt_pkgs=(
            autoconf autoconf-archive binutils build-essential ccache cmake curl
            libgmp-dev libintl-perl libmpfr-dev libreadline-dev libsigsegv-dev
            gettext libticonv-dev libtool m4 texinfo
        )
    arch_pkgs=(
            autoconf autoconf-archive binutils base-devel ccache curl gmp
            perl mpfr readline libsigsegv gettext libiconv libtool m4 tar
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
    local tarball=$(curl -fsS "$gnu_ftp" | grep -oP 'grep-[0-9\.]*\.tar\.gz' | sort -rV | head -n1)
    if [[ -z "$tarball" ]]; then
        fail "Failed to find the latest release."
    fi
    archive_url="${gnu_ftp}${tarball}"
    archive_name="${tarball}"
    version=$(echo "$tarball" | grep -oP '[0-9.]{3,4}')
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
    echo
    ../configure --prefix="$install_dir" \
                 --disable-nls \
                 --enable-gcc-warnings=no \
                 --enable-threads=posix \
                 --with-libsigsegv \
                 --with-libsigsegv-prefix=/usr \
                 --with-libiconv-prefix=/usr \
                 --with-libintl-prefix=/usr
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
    cleanup

    echo
    log "Build completed successfully."
    echo
    log "Make sure to star this repository to show your support!"
    log "https://github.com/slyfox1186/script-repo"
}

main "$@"
