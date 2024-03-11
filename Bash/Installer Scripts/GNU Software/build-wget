#!/usr/bin/env bash

# GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/util-linux/Installer%20Scripts/GNU%20Software/build-wget
# Purpose: Build GNU Wget from source code
# Features: +cares +digest +gpgme +https -ipv6 +iri +large-file +metalink -nls +ntlm +opie +psl +ssl/openssl
# Updated: 01.30.24
# Script version: 1.4
# Added: libmetalink-dev library files

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script must be run as root. Exiting.${NC}" >&2
    exit 1
fi

# Script variables
script_ver="1.4"
cwd="$PWD/wget-build-script"
archive_dir="wget-latest"
install_dir="/usr/local"
pc_type="$(uname -m)-linux-gnu"
verbose=0

# Function definitions
display_help() {
    echo "Usage: $0 [OPTION]..."
    echo -e "\nOptions:"
    echo -e "  -v, --verbose\t\tEnable verbose logging."
    echo -e "  -h, --help\t\tDisplay this help message and exit."
    echo -e "\nExample:"
    echo -e "  $0 --verbose"
    exit 0
}

log() {
    if [[ $verbose -eq 1 ]]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

check_dependencies() {
    apt-get update
    apt-get install autoconf automake bzip2 curl gfortran libcurl4-openssl-dev libexpat1-dev \
                    libgcrypt20-dev libgpgme-dev libssl-dev libunistring-dev pkg-config zlib1g-dev
}

build_libmetalink() {
    log "Building libmetalink..."
    local libmetalink_dir="$cwd/libmetalink"
    mkdir -p "$libmetalink_dir" && cd "$libmetalink_dir"
    curl -fsSL "https://github.com/metalink-dev/libmetalink/releases/download/release-0.1.3/libmetalink-0.1.3.tar.xz" | tar -Jxf - --strip-components 1
    ./configure --prefix="$install_dir" || error "Failed to configure libmetalink."
    make "-j$(nproc)" || error "Failed to build libmetalink."
    make install || error "Failed to install libmetalink."
    log "libmetalink built successfully."
}

build_wget() {
    log "Building wget from source..."
    local wget_dir="$cwd/wget"
    mkdir -p "$wget_dir" && cd "$wget_dir"
    curl -fsSL "https://ftp.gnu.org/gnu/wget/$archive_dir.tar.lz" | tar --lzip -xf - --strip-components=1
    ./configure --prefix="$install_dir" \
                --with-ssl=openssl \
                --with-libssl-prefix="$install_dir" \
                --with-metalink \
                --with-libunistring-prefix=/usr \
                --with-libcares \
                --without-ipv6 \
                --disable-nls || error "Failed to configure wget."
                make "-j$(nproc --all)" || error "Failed to build wget."
                make install || error "Failed to install wget."
    log "wget built and installed successfully."
}

fix_libmetalink_libs() {
    if [[ ! -f /usr/local/lib/libmetalink.so.3 ]]; then
        metalink_library_file=$(find /usr/local/ -type f -name 'libmetalink.so.3*' | head -n1)
        if ! sudo ln -sf "$metalink_library_file" /usr/local/lib/libmetalink.so.3; then
            fail_fn "Failed to find or locate the libmetalink library 'so' file and create the required soft link. Line: $LINENO"
        fi
    fi
}

cleanup() {
    log "Cleaning up build directories..."
    rm -rf "$cwd"
    log "Cleanup complete."
}

# Parse command line arguments
parse_args() {
    while (( "$#" )); do
        case "$1" in
            -v|--verbose)
                verbose=1
                shift
                ;;
            -h|--help)
                display_help
                ;;
            *)
                warn "Ignoring unrecognized option: $1"
                shift
                ;;
        esac
    done
}

# Main execution flow
main() {
    parse_args "$@"
    check_dependencies
    build_libmetalink
    build_wget
    fix_libmetalink_libs
    cleanup
    log "Wget build script completed successfully."
}

main "$@"

# Register all new libraries
ldconfig

echo "Script complete."
