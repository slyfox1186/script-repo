#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Eeuo pipefail
trap 'printf "Build failed at line %s. Build files were retained for inspection.\n" "$LINENO" >&2; exit 1' ERR

gnu_curl() {
    command curl -q --fail --location --show-error --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 600 --proto '=https' --proto-redir '=https' \
        --user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$@"
}

gnu_new_workdir() {
    local base="${TMPDIR:-/tmp}"
    [[ "$base" == /* && -d "$base" ]] || { printf 'TMPDIR must be an existing absolute directory.\n' >&2; return 1; }
    mktemp -d -- "$base/${0##*/}.XXXXXX"
}

gnu_jobs="${JOBS:-$(nproc)}"
[[ "$gnu_jobs" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer.\n' >&2; exit 1; }

# Build GNU Autoconf from source
# You can set the version of autoconf by executing the
# script like this: ./build-autoconf.sh --version 2.71

set -Ee -o pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

version="2.71" # Default version
program_name="autoconf"
install_prefix="/usr/local/programs"
verbose="0"
build_dir=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "This script downloads, builds, and installs GNU Autoconf from source."
    echo
    echo "Options:"
    echo "  -v, --version VERSION    Specify the version of Autoconf to build (default: $version)"
    echo "  -h, --help               Show this help message"
    echo
    echo "Example:"
    echo "  $0 --version 2.72"
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { printf 'Option %s requires a value.\n' "$1" >&2; exit 1; }
                program_version="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    program_version="${program_version:-$version}"
    [[ "$program_version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "Invalid version: $program_version"
}

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

# Install dependencies
install_deps() {
    log "Installing dependencies..."
    if command -v apt-get &>/dev/null; then
        sudo apt update
        sudo apt install autoconf-archive autogen automake autopoint autotools-dev binutils bison build-essential bzip2 ccache curl libtool libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev yasm
    elif command -v dnf &>/dev/null; then
        sudo dnf install autoconf-archive autogen automake autopoint autotools-dev binutils bison bzip2 ccache curl libtool libtool-ltdl-devel lzip lzma-devel m4 nasm texinfo xz yasm zlib-devel
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --needed --noconfirm autoconf-archive autogen automake autopoint binutils bison bzip2 ccache curl libtool lzip lzma m4 nasm texinfo xz yasm zlib
    else
        echo "Unsupported package manager. Please install the required dependencies manually."
        exit 1
    fi
}

# Preparing build environment
prepare_build() {

    build_dir=$(gnu_new_workdir)

    mkdir -p "$build_dir"
    log "Preparing build directory at $build_dir"
}

# Download and extract source archive
download_and_extract() {
    local archive_url="https://ftp.gnu.org/gnu/autoconf/${program_name}-${program_version}.tar.xz"
    local archive_name="${program_name}-${program_version}.tar.xz"
    log "Downloading $archive_url"
    gnu_curl -fsSL "$archive_url" -o "$build_dir/$archive_name"
    log "Extracting archive..."
    tar -xf "$build_dir/$archive_name" -C "$build_dir" --strip-components 1
}

# Configure, build, and install
build_and_install() {
    cd "$build_dir"
    log "Configuring build..."
    ./configure --prefix="$install_prefix/${program_name}-${program_version}"
    log "Compiling..."
    make "-j$gnu_jobs"
    log "Installing..."
    sudo make install
}

# Create symlinks in a common bin directory
create_symlinks() {
    log "Creating symlinks..."
    for file in "$install_prefix/${program_name}-${program_version}"/bin/*; do
        [[ -e "$file" || -L "$file" ]] || continue
        base_name=$(basename "$file" | sed 's/-[0-9].*$//') # Trim extra versioning if present
        sudo ln -sfn "$file" "/usr/local/bin/$base_name"
    done
}

# Cleanup resources
cleanup() {
    local response
    while true; do
        if ! read -r -p "Remove build directory '$build_dir'? [y/N] " response; then
            printf '\nBuild files retained at %s\n' "$build_dir"
            return 0
        fi
        case "$response" in
            1|y|Y|yes|YES) rm -rf -- "$build_dir"; return 0 ;;
            2|n|N|no|NO|"") printf 'Build files retained at %s\n' "$build_dir"; return 0 ;;
            *) printf 'Enter y or n.\n' >&2 ;;
        esac
    done
}

main() {
    parse_args "$@"
    if [[ "$EUID" -eq 0 ]]; then
        echo "This script must not be run as root or with sudo."
        exit 1
    fi
    install_deps
    prepare_build
    download_and_extract
    build_and_install
    create_symlinks
    cleanup
}

main "$@"

echo
log "Build completed successfully."
echo
log "Make sure to star this repository to show your support!"
log "https://github.com/slyfox1186/script-repo"
