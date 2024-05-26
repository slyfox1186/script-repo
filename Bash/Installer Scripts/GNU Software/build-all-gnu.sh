#!/usr/bin/env bash

# Purpose: Build various GNU programs from source
# Updated: 05.26.24
# Script version: 2.8

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# List of available programs
available_programs=(autoconf autoconf-archive automake bash gawk gettext grep gzip libiconv libtool make nano parallel pkg-config sed tar texinfo wget which)

# Consolidated list of required packages for all programs
MASTER_PKGS="autoconf autoconf-archive automake build-essential ccache libtool m4 gettext libintl-perl bzip2 curl libc6-dev lzip lzma lzma-dev xz-utils zlib1g-dev texinfo libticonv-dev"

# Specific package lists for each program (excluding those already in MASTER_PKGS)
BASH_PKGS="libacl1-dev libattr1-dev liblzma-dev libticonv9 libzstd-dev lzip lzop"
GAWK_PKGS="libgmp-dev libmpfr-dev libreadline-dev libsigsegv-dev lzip"
GREP_PKGS="libltdl-dev libsigsegv-dev libticonv-dev"
GZIP_PKGS="libzstd-dev zstd"
MAKE_PKGS=" libdmalloc-dev libsigsegv2 libticonv9"
NANO_PKGS="libncurses5-dev libpth-dev nasm"
PKG_CONFIG_PKGS="libglib2.0-dev libpopt-dev"
SED_PKGS="autopoint autotools-dev libaudit-dev librust-polling-dev valgrind"
TAR_PKGS="libacl1-dev libattr1-dev libbz2-dev liblzma-dev libticonv9 libzstd-dev lzip lzop"
LIBICONV_PKGS="libgettextpo-dev"
GETTEXT_PKGS="libgettextpo-dev"
PARALLEL_PKGS="autogen binutils bison lzip yasm"
WGET_PKGS="gfortran libcurl4-openssl-dev libexpat1-dev libgcrypt20-dev libgpgme-dev libssl-dev libunistring-dev"
WHICH_PKGS="curl gcc make tar"

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

show_usage() {
    echo "Usage: ${0##*/} [OPTIONS]"
    echo "Build various GNU programs from source."
    echo
    echo "Options:"
    echo "  -h, --help           Show this help message and exit"
    echo "  -p, --programs       Specify the programs to build (comma-separated, or 'all' for all programs)"
    echo "  -v, --version        Specify the version of the program to build (default: latest)"
    echo
    echo "Available Programs: ${available_programs[*]}"
    echo
    echo "Example:"
    echo "  ${0##*/} -p bash,make,grep"
}

# Parse command-line options
programs=""
version=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -p|--programs)
            shift
            programs="$1"
            ;;
        -v|--version)
            shift
            version="$1"
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
    shift
done

# Check for root user
if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Display available programs and prompt for programs if not specified via arguments
if [[ -z "$programs" ]]; then
    echo "Available Programs: ${available_programs[*]}"
    echo "You can also choose 'all' to install all available programs."
    echo
    read -p "Enter the programs to build (comma-separated): " programs
    clear
fi

# Define required packages and common functions
required_packages() {
    local -a pkgs
    local pkg

    pkgs=($MASTER_PKGS)

    if [[ "$1" == "all" ]]; then
        pkgs+=($BASH_PKGS $GAWK_PKGS $GREP_PKGS $GZIP_PKGS $MAKE_PKGS $NANO_PKGS $PKG_CONFIG_PKGS $SED_PKGS $TAR_PKGS $LIBICONV_PKGS $GETTEXT_PKGS $PARALLEL_PKGS $WGET_PKGS $WHICH_PKGS)
    else
        for prog in "${progs[@]}"; do
            case "$prog" in
                bash)
                    pkgs+=($BASH_PKGS)
                    ;;
                gawk)
                    pkgs+=($GAWK_PKGS)
                    ;;
                grep)
                    pkgs+=($GREP_PKGS)
                    ;;
                gzip)
                    pkgs+=($GZIP_PKGS)
                    ;;
                make)
                    pkgs+=($MAKE_PKGS)
                    ;;
                nano)
                    pkgs+=($NANO_PKGS)
                    ;;
                pkg-config)
                    pkgs+=($PKG_CONFIG_PKGS)
                    ;;
                sed)
                    pkgs+=($SED_PKGS)
                    ;;
                tar)
                    pkgs+=($TAR_PKGS)
                    ;;
                libiconv)
                    pkgs+=($LIBICONV_PKGS)
                    ;;
                gettext)
                    pkgs+=($GETTEXT_PKGS)
                    ;;
                parallel)
                    pkgs+=($PARALLEL_PKGS)
                    ;;
                wget)
                    pkgs+=($WGET_PKGS)
                    ;;
                which)
                    pkgs+=($WHICH_PKGS)
                    ;;
            esac
        done
    fi

    # Remove duplicate packages and sort alphabetically
    pkgs=($(echo "${pkgs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    local -a missing_pkgs=()
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
    CFLAGS="-O3 -pipe -march=native -flto"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath=$install_dir/lib64:$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

get_latest_version_url() {
    local prog_name version
    prog_name=$1
    case "$prog_name" in
        pkg-config)
            version=$(curl -fsS "https://pkgconfig.freedesktop.org/releases/" | grep -oP "pkg-config-\K\d+([\d.])+(?=\.tar\.)" | sort -ruV | head -n1)
            ;;
        autoconf)
            version="2.71"
            ;;
        *)
            version=$(curl -fsS "https://ftp.gnu.org/gnu/$prog_name/" | grep -oP "$prog_name-\K([0-9.]+)(?=\.tar\..*)" | sort -ruV | head -n1)
            ;;
    esac
    if [[ -z "$version" ]]; then
        fail "Failed to find the latest version for $prog_name. Please check the program name or the GNU FTP server."
    fi
    echo "$version"
}

download_and_extract() {
    local archive_url

    if [[ "$prog_name" == "pkg-config" ]]; then
        archive_url="https://pkgconfig.freedesktop.org/releases/pkg-config-$version.tar.gz"
    else
        archive_url="https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar"
        for ext in lz xz bz2 gz; do
            wget --spider "$archive_url.$ext" &>/dev/null && archive_url+=".$ext" && break
        done
    fi

    wget --show-progress -cqO "$cwd/$archive_name.${archive_url##*.}" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
    tar -xf "$cwd/$archive_name.${archive_url##*.}" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$archive_name.${archive_url##*.}"
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"
    
    case "$prog_name" in
        bash|libtool|nano|libiconv)
            ;;
        pkg-config|which)
            autoconf || fail "Failed to execute: autoconf. Line: $LINENO"
            ;;
        make)
            autoreconf -fi -I /usr/share/aclocal || fail "Failed to execute: autoreconf. Line: $LINENO"
            ;;
        *)
            autoreconf -fi || fail "Failed to execute: autoreconf. Line: $LINENO"
            ;;
    esac
    
    mkdir -p build
    cd build || fail "Failed to cd into the build directory. Line: $LINENO"
    ../configure --prefix="$install_dir" --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
}

compile_and_install() {
    make "-j$(nproc --all)" || fail "Failed to execute: make build. Line: $LINENO"
    sudo make install || fail "Failed execute: make install. Line: $LINENO"
    case "$prog_name" in
        libiconv)
            sudo libtool --finish /usr/local/libiconv-1.17/lib
            ;;
    esac
}

create_soft_links() {
    sudo ln -sf "$install_dir/bin/"* "/usr/local/bin/"
    sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    sudo ln -sf "$install_dir/include/"* "/usr/local/include/"
}

ld_linker_path() {
    local ld_file="/etc/ld.so.conf.d/custom_libs.conf"
    if [[ ! -f "$ld_file" ]]; then
        echo -e "$install_dir/lib64\n$install_dir/lib" | sudo tee "$ld_file" >/dev/null
    else
        grep -qxF "$install_dir/lib64" "$ld_file" || echo "$install_dir/lib64" | sudo tee -a "$ld_file" >/dev/null
        grep -qxF "$install_dir/lib" "$ld_file" || echo "$install_dir/lib" | sudo tee -a "$ld_file" >/dev/null
    fi
    sudo ldconfig
}

cleanup() {
    sudo rm -fr "$cwd"
}

build_program() {
    local prog_name version
    prog_name="$1"
    version="$2"

    echo
    log "Building $prog_name"
    if [[ -z "$version" ]]; then
        version=$(get_latest_version_url "$prog_name")
    fi
    archive_name="$prog_name-$version"
    install_dir="/usr/local/$archive_name"
    cwd="/tmp/$prog_name-build-script"
    tar_file="$archive_name.$(date +%s)"
    mkdir -p "$cwd/$archive_name/build"
    set_compiler_flags
    download_and_extract
    configure_build
    compile_and_install
    ld_linker_path
    create_soft_links
    cleanup
}

# Build each specified program
IFS=',' read -ra progs <<< "$programs"
if [[ "$programs" == "all" ]]; then
    progs=("${available_programs[@]}")
fi

required_packages "${progs[@]}"

for prog in "${progs[@]}"; do
    build_program "$prog" "$version"
done

log "All specified programs have been built and installed successfully."
exit 0
