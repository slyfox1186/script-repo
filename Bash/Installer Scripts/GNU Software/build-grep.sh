#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-grep.sh
##  Purpose: Build GNU Grep
##  Updated: 04.19.24
##  Script version: 2.2

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

trap 'fail "Error occurred on line: $LINENO".' ERR

install_dir="/usr/local"
cwd="/tmp/$program_name-$version-build"
workspace="$cwd/workspace"
gnu_ftp="https://ftp.gnu.org/gnu/grep/"
verbose=0
version=""

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"  
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
            autoconf autoconf-archive binutils build-essential ccache curl
            libgmp-dev libintl-perl libmpfr-dev libreadline-dev libsigsegv-dev
            gettext libtool m4 texinfo
        )
    arch_pkgs=(
            autoconf autoconf-archive binutils base-devel ccache curl gmp
            perl mpfr readline libsigsegv gettext libiconv libtool m4 tar
        )
    if command -v apt &>/dev/null; then
        sudo apt update
        sudo apt install -y "${apt_pkgs[@]}"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${apt_pkgs[@]}"
    elif command -v zypper &>/dev/null; then
        sudo zypper install -y --no-recommends "${apt_pkgs[@]}"
    elif command -v pacman &>/dev/null; then
        sudo pacman -Syu --needed --noconfirm "${arch_pkgs[@]}"
    else
        fail "Unsupported package manager. Install the required dependencies manually."
    fi
}

find_release() {
    log "Finding the specified release..."
    local tarball
    tarball=$(curl -fsS "$gnu_ftp" | grep -oP "grep-$version\.tar\.xz" | head -n1)
    
    if [[ -z "$tarball" ]]; then
        fail "Failed to find the specified release: $version"
    fi
    
    archive_url="${gnu_ftp}${tarball}"
    archive_name="$tarball"
    program_name="grep"
}

find_latest_release() {
    log "Finding the latest release..."
    local tarball
    tarball=$(curl -fsS "$gnu_ftp" | grep -oP 'grep-[0-9.]*\.tar\.xz' | sort -rV | head -n1)
    
    if [[ -z "$tarball" ]]; then
        fail "Failed to find the latest release."
    fi
    
    archive_url="${gnu_ftp}${tarball}"
    archive_name="$tarball"
    version=$(echo "$tarball" | grep -oP '[0-9.]{3,4}')
    program_name="grep"
}

download_archive() {
    log "Downloading archive..."
    if [[ ! -f "$cwd/$archive_name" ]]; then
        curl -LSso "$cwd/$archive_name" "$archive_url"
    fi
}

extract_archive() {
    log "Extracting archive..."
    tar -xf "$cwd/$archive_name" -C "$workspace" --strip-components 1
}

set_env_vars() {
    log "Setting environment variables..."
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-O2 -pipe -fno-plt -march=native"
    CXXFLAGS="$CFLAGS" 
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/$program_name-$version/lib"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS
    export PATH="/usr/lib/ccache:$HOME/.local/bin:$PATH"
    export PKG_CONFIG_PATH="$install_dir/lib64/pkgconfig:$install_dir/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig"
}

configure_build() {
    log "Configuring build..."
    cd "$workspace"
    autoreconf -fi
    mkdir -p build && cd build
    
    log "Configuring..."
    ../configure --prefix="$install_dir/$program_name-$version" \
                 --enable-threads=posix \
                 --with-libsigsegv-prefix=/usr \
                 --with-libiconv-prefix=/usr
}

compile_build() {
    log "Compiling..."
    make "-j$(nproc --all)"
}

install_build() {
    log "Installing..."
    sudo make install

    log "Creating symlinks..."
    sudo ln -sfn "$install_dir/$program_name-$version/bin"/{grep,egrep,fgrep} "/usr/local/bin/"
}

uninstall_build() {
    log "Uninstalling..."
    sudo make uninstall
    sudo rm -f "/usr/local/bin"/{grep,egrep,fgrep}
}

cleanup() {
    log "Cleaning up..."
    sudo rm -rf "$cwd"
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    printf "  %-25s %s\n" "-p, --prefix DIR" "Set the installation prefix (default: $install_dir/grep-\$version)"
    printf "  %-25s %s\n" "-V, --version VERSION" "Specify the version of GNU grep to install"
    printf "  %-25s %s\n" "-v, --verbose" "Enable verbose logging"
    printf "  %-25s %s\n" "-h, --help" "Show this help message"
    echo
    echo "$0 -V 3.8 --verbose"
    exit 0
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -p|--prefix)
                install_dir="$2"
                shift 2
                ;;
            -V|--version)
                version="$2"
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

main() {
    parse_args "$@"

    if [[ "$EUID" -eq 0 ]]; then
        fail "Do not run this script as root or with sudo."
    fi

    mkdir -p "$cwd" "$workspace"

    install_deps

    if [[ -n "$version" ]]; then
        find_release
    else
        find_latest_release
    fi

    download_archive
    extract_archive
    set_env_vars
    configure_build

    if [[ "$1" == "uninstall" ]]; then
        uninstall_build
    else
        compile_build
        install_build
    fi
    
    cleanup

    log "Build completed successfully."
    echo -e "Star this repo if you found it useful: ${YELLOW}https://github.com/slyfox1186/script-repo${NC}"
}

main "$@"
