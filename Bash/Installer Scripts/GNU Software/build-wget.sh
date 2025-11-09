#!/usr/bin/env bash

# Github: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-wget.sh
# Purpose: build gnu wget from source code
# Updated: 11.09.2025
# Script version: 1.5

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set the variables
script_ver=1.5
prog_name="wget"
default_version=$(curl -fsS "https://ftp.gnu.org/gnu/wget/" | grep -oP 'wget-[\d.]+(?=\.tar\.[a-z]+)' | sort -ruV | head -n1)
install_dir="/usr/local/programs/$prog_name-$default_version"
install_dir="${install_dir//wget-wget-/wget-}"
cwd="$PWD/$prog_name-build-script"
compiler="gcc"

# Enhanced logging and fail handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "\\n${YELLOW}[WARNING]${NC} $1"
}

debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "  -v, --version VERSION       Set the version of $prog_name to install (default: $default_version)"
    echo "  -l, --list                  List available versions of $prog_name"
    echo "  -u, --uninstall             Uninstall $prog_name"
    echo "  -c, --compiler COMPILER     Set the compiler to use (clang) instead of the default: $compiler"
    echo "  -d, --debug                 Enable debug output"
    echo "  -h, --help                  Display this help and exit"
}

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
    pkgs=(
        autoconf automake build-essential bzip2 curl gfortran \
        libcurl4-openssl-dev libexpat1-dev libgcrypt20-dev \
        libgpgme-dev libpsl-dev libssl-dev libunistring-dev \
        libxml2-dev libtool lzip m4 pkg-config zlib1g-dev
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
    CC="$compiler"
    CXX="$compiler++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath,$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

build_libmetalink() {
    log "Building libmetalink..."
    local libmetalink_dir
    libmetalink_dir="$cwd/libmetalink"
    mkdir -p "$libmetalink_dir" && cd "$libmetalink_dir" || exit 1
    curl -fsSL "https://github.com/metalink-dev/libmetalink/releases/download/release-0.1.3/libmetalink-0.1.3.tar.xz" | tar -Jxf - --strip-components 1

    # Ensure we have all necessary build files
    if [[ ! -f "configure" ]]; then
        log "Running autoreconf to generate configure script..."
        autoreconf -fiv || fail "Failed to run autoreconf for libmetalink."
    fi

    # Ensure we have a compile script (sometimes missing from tarballs)
    if [[ ! -f "compile" ]]; then
        log "Missing compile script, creating it..."
        curl -fsSL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=compile;hb=HEAD" -o compile
        chmod +x compile
    fi

    mkdir build; cd build || exit 1
    ../configure --prefix="$install_dir" || fail "Failed to configure libmetalink."
    make "-j$(nproc)" || fail "Failed to build libmetalink."
    sudo make install || fail "Failed to install libmetalink."
    log "libmetalink built successfully."
}

download_archive() {
    wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    case "$archive_ext" in
        "gz")
            tar -zxf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
            ;;
        "xz")
            tar -Jxf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
            ;;
        "lz")
            tar --lzip -xf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
            ;;
        *)
            fail "Unsupported archive format: $archive_ext"
            ;;
    esac
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"

    # Ensure we have all necessary build files
    if [[ ! -f "configure" ]]; then
        log "Running autoreconf to generate configure script for wget..."
        autoreconf -fiv || fail "Failed to run autoreconf for wget."
    fi

    # Ensure we have a compile script if needed
    if [[ ! -f "compile" ]]; then
        log "Missing compile script, creating it..."
        curl -fsSL "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=compile;hb=HEAD" -o compile
        chmod +x compile
    fi

    cd build || exit 1
    ../configure --prefix="$install_dir" \
                 --with-ssl=openssl \
                 --with-libssl-prefix="$cwd" \
                 --with-metalink \
                 --with-libunistring-prefix=/usr \
                 --with-libcares \
                 --without-ipv6 \
                 --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
}

compile_build() {
    make "-j$(nproc --all)" || fail "Failed to execute: make build. Line: $LINENO"
}

install_build() {
    sudo make install || fail "Failed execute: make install. Line: $LINENO"
}

ld_linker_path() {
    echo "$install_dir/lib/" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    sudo ldconfig
}

create_soft_links() {
    [[ -d "$install_dir/bin" ]] && sudo ln -sf "$install_dir/bin/"* "/usr/local/bin/"
    [[ -d "$install_dir/lib/pkgconfig" ]] && sudo ln -sf "$install_dir/lib/pkgconfig/"*.pc "/usr/local/lib/pkgconfig/"
    [[ -d "$install_dir/include" ]] && sudo ln -sf "$install_dir/include/"* "/usr/local/include/"
}

uninstall_wget() {
    local tar_dir
    wget_dir="$install_dir/$archive_name"
    if [[ -d "$wget_dir" ]]; then
        log "Uninstalling $prog_name from $wget_dir"
        sudo rm -rf "$wget_dir"
        sudo rm "/etc/ld.so.conf.d/custom_$prog_name.conf"
        sudo ldconfig
        log "$prog_name has been uninstalled"
    else
        log "$prog_name is not installed"
    fi
}

list_versions() {
    log "Available versions of $prog_name:"
    echo
    curl -fsS "https://ftp.gnu.org/gnu/wget/" | grep -oP 'wget-[\d.]+(?=\.tar\.[a-z]+)' | sort -ruV
}

main_menu() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                version="$2"
                shift 2
                ;;
            -l|--list)
                list_versions
                exit 0
                ;;
            -u|--uninstall)
                uninstall_wget
                exit 0
                ;;
            -c|--compiler)
                compiler="$2"
                shift 2
                ;;
            -d|--debug)
                export DEBUG=1
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                fail "Invalid option: $1"
                ;;
        esac
    done

    if [[ -z "$version" ]]; then
        version="$default_version"
        log "No version specified, using default version: $version"
    fi

    archive_name="$prog_name-$version"
    archive_name="${archive_name//wget-wget-/wget-}"
    debug "Looking for archive: $prog_name-$version"

    # Try .tar.gz first (most common), then .tar.lz as fallback
    if curl -fsS "https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar.gz" | head -c1 >/dev/null 2>&1; then
        archive_url="https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar.gz"
        archive_ext="gz"
        log "Found .tar.gz archive format"
    elif curl -fsS "https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar.lz" | head -c1 >/dev/null 2>&1; then
        archive_url="https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar.lz"
        archive_ext="lz"
        log "Found .tar.lz archive format"
    else
        fail "No suitable archive format found for $prog_name-$version"
    fi
    archive_url="${archive_url//wget-wget-/wget-}"
    tar_file="$archive_name.tar.$archive_ext"
    debug "Archive URL: $archive_url"
    debug "Archive file: $tar_file"

    # Create output directory
    [[ -d "$cwd/$archive_name" ]] && sudo rm -fr "$cwd/$archive_name"
    mkdir -p "$cwd/$archive_name/build"

    required_packages
    set_compiler_flags
    build_libmetalink
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    if [[ ! -d "$install_dir/lib/" ]]; then
        warn "Failed to located the lib directory \"$install_dir/lib\" so no custom ld linking will occur."
    else
        ld_linker_path
    fi
    create_soft_links
    cleanup
    exit_function
}

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

main_menu "$@"
