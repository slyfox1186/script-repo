#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Ee -o pipefail
trap 'printf "Build failed at line %s. Build files were retained for inspection.\n" "$LINENO" >&2; exit 1' ERR

gnu_curl() {
    command curl -q --fail --location --show-error --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 600 --proto '=https' --proto-redir '=https' \
        --user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$@"
}

gnu_wget() {
    command wget --timeout=30 --tries=3 --https-only \
        --user-agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$@"
}

gnu_new_workdir() {
    local base="${TMPDIR:-/tmp}"
    [[ "$base" == /* && -d "$base" ]] || { printf 'TMPDIR must be an existing absolute directory.\n' >&2; return 1; }
    mktemp -d -- "$base/${0##*/}.XXXXXX"
}

gnu_jobs="${JOBS:-$(nproc)}"
[[ "$gnu_jobs" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer.\n' >&2; exit 1; }

##  Github: https://github.com/slyfox1186/script-repo/blob/main/Bash/installer-scripts/gnu-software/build-make.sh
##  Purpose: build gnu make
##  Updated: 05.11.24
##  Script version: 2.2

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

echo "make build script - version 2.2"
echo "================================================="
echo

# Create functions
exit_function() {
    echo
    log "The script has completed"
    log "${GREEN}Make sure to ${YELLOW}star ${GREEN}this repository to show your support!${NC}"
    log "${CYAN}https://github.com/slyfox1186/script-repo${NC}"
    exit 0
}

cleanup() {
    rm -rf -- "$cwd"
}

required_packages() {
    local -a missing_pkgs pkgs
    local pkg
    log "Installing dependencies..."
    pkgs=(
         autoconf automake build-essential gettext libdmalloc-dev
         libintl-perl libsigsegv2 libtool lzip texinfo
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
    LDFLAGS="-Wl,-rpath=$install_dir/lib64:$install_dir/lib"
    PKG_CONFIG="$(command -v pkg-config)"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG PKG_CONFIG_PATH
}

download_archive() {
    gnu_wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    tar -xf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"

    cd build || fail "Failed to cd into the build directory. Line: $LINENO"
    ../configure --prefix="$install_dir" --disable-nls --enable-year2038 --with-dmalloc \
             --with-libsigsegv-prefix=/usr --with-libiconv-prefix=/usr --with-libintl-prefix=/usr || (
                fail "Failed to execute: configure. Line: $LINENO"
            )
}

compile_build() {
    make "-j$gnu_jobs" || fail "Failed to execute: make build. Line: $LINENO"
}

install_build() {
    sudo make install || fail "Failed execute: make install. Line: $LINENO"
}

ld_linker_path() {
    echo -e "$install_dir/lib64\\n$install_dir/lib" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    sudo ldconfig
}

create_soft_links() {
    for file in "$install_dir/bin/"*; do
        [[ -e "$file" || -L "$file" ]] || continue
        sudo mkdir -p "/usr/local/bin/"
        sudo ln -sfn -- "$file" "/usr/local/bin/"
    done
    for file in "$install_dir/lib/pkgconfig/"*.pc; do
        [[ -e "$file" || -L "$file" ]] || continue
        sudo mkdir -p "/usr/local/lib/pkgconfig/"
        sudo ln -sfn -- "$file" "/usr/local/lib/pkgconfig/"
    done
    for file in "$install_dir/include/"*; do
        [[ -e "$file" || -L "$file" ]] || continue
        sudo mkdir -p "/usr/local/include/"
        sudo ln -sfn -- "$file" "/usr/local/include/"
    done
}

show_usage() {
    echo "Usage: ${0##*/} [OPTIONS]"
    echo "Build GNU Make from source."
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -v, --version    Specify the version of make to build (default: 4.4.1)"
    echo
    echo "Example:"
    echo "  $0 -v 4.3"
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            [[ $# -ge 2 && "$2" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "Option $1 requires a numeric version."
            shift
            make_version="$1"
            ;;
        *)
            fail "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    shift
done

main_menu() {

    script_ver=2.2
    prog_name="make"
    version="${make_version:-}"
    if [[ -z "$version" ]]; then
        version=$(gnu_curl -fsS "https://ftp.gnu.org/gnu/$prog_name/" | grep -oP 'make-\K([0-9.])+(?=\.tar\..*)' | sort -ruV | sed -n '1p')
    fi
    archive_name="$prog_name-$version"
    install_dir="/usr/local/programs/$archive_name"
    cwd="$PWD/$archive_name-build-script"

    # Create output directory

    cwd=$(gnu_new_workdir)

    mkdir -p "$cwd/$archive_name/build"

    if [[ -n "$make_version" ]]; then
        archive_url="https://ftp.gnu.org/gnu/$prog_name/$prog_name-$make_version.tar.lz"
        archive_ext="${archive_url//*.}"
    else
        archive_url="https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar.lz"
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
