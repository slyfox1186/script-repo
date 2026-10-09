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

gnu_link_dir() {
    local source_dir="$1" destination="$2" pattern="${3:-*}" file target
    [[ -d "$source_dir" ]] || return 0
    for file in "$source_dir"/*; do
        [[ -e "$file" || -L "$file" ]] || continue
        # The caller supplies a filename glob, for example *.pc.
        # shellcheck disable=SC2053
        [[ "${file##*/}" == $pattern ]] || continue
        target="$destination/${file##*/}"
        [[ ! -d "$target" || -L "$target" ]] || { printf 'Cannot replace directory %s with a symlink.\n' "$target" >&2; return 1; }
        sudo mkdir -p -- "$destination"
        sudo ln -sfn -- "$file" "$target"
    done
}

gnu_new_workdir() {
    local base="${TMPDIR:-/tmp}"
    [[ "$base" == /* && -d "$base" ]] || { printf 'TMPDIR must be an existing absolute directory.\n' >&2; return 1; }
    mktemp -d -- "$base/${0##*/}.XXXXXX"
}

gnu_jobs="${JOBS:-$(nproc)}"
[[ "$gnu_jobs" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer.\n' >&2; exit 1; }

# Github: https://github.com/slyfox1186/script-repo/blob/main/Bash/installer-scripts/gnu-software/build-tar.sh
# Purpose: build gnu tar
# Updated: 11.09.2025
# Script version: 2.3

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set the variables
script_ver=2.2
prog_name="tar"
default_version="latest"
version=""
uninstall=false
install_dir="/usr/local/programs"
cwd="$PWD/$prog_name-build-script"
compiler="gcc"

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "\\n${YELLOW}[WARNING]${NC} $1"
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
    rm -rf -- "$cwd"
}

required_packages() {
    local -a missing_pkgs pkgs
    local pkg
    pkgs=(
        autoconf automake build-essential gettext libacl1-dev
        libattr1-dev libbz2-dev libintl-perl liblzma-dev libtool
        lzip lzop libzstd-dev xz-utils zlib1g-dev
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
    case "$compiler" in
        gcc) CXX="g++" ;;
        clang) CXX="clang++" ;;
        *) fail "Unsupported compiler: $compiler. Choose gcc or clang." ;;
    esac
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath,$install_dir/$archive_name/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS PKG_CONFIG_PATH PATH
}

download_archive() {
    gnu_wget --show-progress -cqO "$cwd/$tar_file" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
}

extract_archive() {
    tar -Jxf "$cwd/$tar_file" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$tar_file"
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"

    cd build || exit 1
    ../configure --prefix="$install_dir/$archive_name" --disable-nls --disable-gcc-warnings --with-bzip2="$(type -P bzip2)" \
                 --with-lzip="$(type -P lzip)" --with-lzma="$(type -P lzma)" --with-xz="$(type -P xz)" \
                 --with-zstd="$(type -P zstd)" --with-lzop="$(type -P lzop)" --with-gzip="$(type -P gzip)" \
                 --with-libiconv-prefix=/usr --with-libintl-prefix=/usr || fail "Failed to execute: configure. Line: $LINENO"
}

compile_build() {
    make "-j$gnu_jobs" || fail "Failed to execute: make build. Line: $LINENO"
}

install_build() {
    sudo make install || fail "Failed execute: make install. Line: $LINENO"
}

ld_linker_path() {
    echo "$install_dir/$archive_name/lib" | sudo tee "/etc/ld.so.conf.d/custom_$prog_name.conf" >/dev/null
    sudo ldconfig
}

create_soft_links() {
    gnu_link_dir "$install_dir/$archive_name/bin" /usr/local/bin
    gnu_link_dir "$install_dir/$archive_name/lib/pkgconfig" /usr/local/lib/pkgconfig '*.pc'
    gnu_link_dir "$install_dir/$archive_name/include" /usr/local/include
}

uninstall_tar() {
    local tar_dir
    tar_dir="$install_dir/$archive_name"
    if [[ -d "$tar_dir" ]]; then
        log "Uninstalling $prog_name from $tar_dir"
        sudo rm -rf "$tar_dir"
        sudo rm -f -- "/etc/ld.so.conf.d/custom_$prog_name.conf"
        sudo ldconfig
        log "$prog_name has been uninstalled"
    else
        log "$prog_name is not installed"
    fi
}

list_versions() {
    log "Available versions of $prog_name:"
    echo
    gnu_curl -fsS "https://ftp.gnu.org/gnu/$prog_name/" | grep -oP '[0-9]+(\.[0-9]+)+(?=\.tar\.[a-z]+)' | sort -ruV
}

main_menu() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { printf 'Option %s requires a value.\n' "$1" >&2; exit 1; }
                version="$2"
                shift 2
                ;;
            -l|--list)
                list_versions
                exit 0
                ;;
            -u|--uninstall)
                uninstall=true
                shift
                ;;
            -c|--compiler)
                [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { printf 'Option %s requires a value.\n' "$1" >&2; exit 1; }
                compiler="$2"
                shift 2
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

    [[ "$compiler" == gcc || "$compiler" == clang ]] || fail "Unsupported compiler: $compiler. Choose gcc or clang."

    if [[ -z "$version" ]]; then
        version=$(gnu_curl -fsS "https://ftp.gnu.org/gnu/$prog_name/" | grep -oP '[0-9]+(\.[0-9]+)+(?=\.tar\.[a-z]+)' | sort -ruV | sed -n '1p')
        log "No version specified, using default version: $version"
    fi

    [[ "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "Invalid version: $version"
    archive_name="$prog_name-$version"
    if [[ "$uninstall" == true ]]; then
        uninstall_tar
        exit 0
    fi
    archive_url="https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar.xz"
    archive_ext="${archive_url//*.}"
    tar_file="$archive_name.tar.$archive_ext"

    # Create output directory

    cwd=$(gnu_new_workdir)

    mkdir -p "$cwd/$archive_name/build"

    required_packages
    set_compiler_flags
    download_archive
    extract_archive
    configure_build
    compile_build
    install_build
    # Check if lib directory exists and add to ld config if it does
    lib_dir="$install_dir/$archive_name/lib"
    if [[ ! -d "$lib_dir" ]]; then
        log "No lib directory found - this is normal for static programs like tar"
    else
        # Check if there are any .so files in the lib directory
        so_files=("$lib_dir/"*.so)
        if [[ ! -e "${so_files[0]}" ]]; then
            log "Lib directory exists but contains no shared libraries - adding to ld config anyway"
        fi
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
