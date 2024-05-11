#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-sed.sh
##  Purpose: build gnu sed
##  Updated: 05.11.24
##  Script version: 1.3

set -euo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Create functions
exit_function() {
    echo
    log "The script has completed"
    log "${GREEN}Make sure to ${YELLOW}star ${GREEN}this repository to show your support!${NC}"
    log "${CYAN}https://github.com/slyfox1186/script-repo${NC}"
    exit 0
}

cleanup() {
    sudo rm -fr "$cwd"
}

required_packages() {
    local -a missing_pkgs pkgs
    local pkg
    log "Installing dependencies..."
    pkgs=(
        autoconf automake autopoint autotools-dev build-essential
        bzip2 ccache curl libaudit-dev libintl-perl libticonv-dev
        libtool pkg-config valgrind zlib1g-dev librust-polling-dev
    )

    missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ "${#missing_pkgs[@]}" -gt 0 ]]; then
        sudo apt update
        sudo apt install "${missing_pkgs[@]}"
    fi
}

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG="$(command -v pkg-config)"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG PKG_CONFIG_PATH
}

download_archive() {
    wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    tar -Jxf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"
    autoreconf -fi
    cd build || fail "Failed to cd into the build directory. Line: $LINENO"
    ../configure --prefix="$install_dir" --enable-threads=posix --disable-nls \
                 --with-libiconv-prefix=/usr --with-libintl-prefix=/usr || fail "Failed to execute: configure. Line: $LINENO"
}

compile_build() {
    make "-j$(nproc --all)" || fail "Failed to execute: make build. Line: $LINENO"
}

install_build() {
    sudo make install || fail "Failed execute: make install. Line: $LINENO"
}

ld_linker_path() {
    if ! echo "$install_dir/lib" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null; then
        echo "LD linker failed."
        exit 1
    fi
    sudo ldconfig
}

create_soft_links() {
    sudo ln -sf "$install_dir/bin/"* "/usr/local/bin/"
    sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    sudo ln -sf "$install_dir/include/"* "/usr/local/include/"
}

show_usage() {
    echo "Usage: ${0##*/} [OPTIONS]"
    echo "Build GNU Make from source."
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -v, --version    Specify the version of sed to build (default: 4.4.1)"
    echo
    echo "Example:"
    echo "  $0 -v 4.3 -c"
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            shift
            sed_version="$1"
            ;;
        *)
            warn "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    shift
done

main_menu() {
    sed_version=""
    script_ver=2.2
    prog_name="sed"
    version=$(curl -fsS "https://ftp.gnu.org/gnu/$prog_name/" | grep -oP 'sed-\K([0-9.])+(?=\.tar\..*)' | sort -ruV | head -n1)
    archive_name="$prog_name-$version"
    install_dir="/usr/local/$archive_name"
    cwd="$PWD/$archive_name-build-script"

    echo "$prog_name build script - version $script_ver"
    echo "================================================="
    echo

    # Create output directory
    [[ -d "$cwd/$archive_name" ]] && sudo rm -fr "$cwd/$archive_name"
    mkdir -p "$cwd/$archive_name/build"

    if [[ -n "$sed_version" ]]; then
        archive_url="https://ftp.gnu.org/gnu/sed/sed-$sed_version.tar.xz"
        archive_ext="${archive_url//*.}"
    else
        archive_url="https://ftp.gnu.org/gnu/sed/sed-$version.tar.xz"
        archive_ext="${archive_url//*.}"
    fi
    tar_file="$archive_name.tar.$archive_ext"

    required_packages
    set_compiler_flags
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    ld_linker_path
    create_soft_links
    cleanup
    exit_function
}

main_menu "$@"
