#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Ee -o pipefail
trap 'printf "Build failed at line %s. Build files were retained for inspection.\n" "$LINENO" >&2; exit 1' ERR

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

# Purpose: Build GNU Parallel from source code
# Updated: 03.20.26
# Script version: 2.8

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Log functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Help menu
display_help() {
    echo "Build GNU Parallel from source code"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -v, --version <version>   Specify the version of GNU Parallel to install"
    echo "  -l, --latest              Install the latest version of GNU Parallel"
    echo "  -h, --help                Display this help menu"
    echo
    echo "This script builds and installs GNU Parallel from source code."
    echo "It downloads the specified version (or the latest version) of GNU Parallel,"
    echo "compiles it, and installs it in the /usr/local directory."
    echo
    echo "Dependencies:"
    echo "  The script automatically checks and installs the required dependencies"
    echo "  using the package manager (apt)."
    echo
    echo "Note: This script should not be run as root or with sudo."
}

# Parse command line arguments
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -v|--version)
                [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { printf 'Option %s requires a value.\n' "$1" >&2; exit 1; }
                version="$2"
                shift 2
                ;;
            -l|--latest)
                version="latest"
                shift
                ;;
            -h|--help)
                display_help
                exit 0
                ;;
            *)
                fail "You did not enter a valid version: $1"
                ;;
        esac
    done
}

set_compiler_settings() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O3 -pipe -fno-plt -march=native"
    CXXFLAGS="$CFLAGS"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CFLAGS CXX CXXFLAGS PKG_CONFIG_PATH PATH
}

# Verify the script is not run as root
verify_not_root() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must not run this script as root or with sudo."
    fi
}

# Check and install missing dependencies
check_dependencies() {
    local dependencies=() missing_deps=()

    dependencies=(
        autoconf autoconf-archive autogen automake binutils bison
        build-essential bzip2 ccache libc6-dev
        libtool libtool-bin lzip liblzma-dev m4 nasm texinfo zlib1g-dev
        wget yasm
    )

    for dep in "${dependencies[@]}"; do
        if ! dpkg -s "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "Installing missing dependencies: ${missing_deps[*]}"
        sudo apt update
        sudo apt install "${missing_deps[@]}"
    else
        log "All dependencies are satisfied."
    fi
}

cleanup() {
    local response
    while true; do
        if ! read -r -p "Remove build directory '$cwd'? [y/N] " response; then
            printf '\nBuild files retained at %s\n' "$cwd"
            return 0
        fi
        case "$response" in
            1|y|Y|yes|YES) rm -rf -- "$cwd"; return 0 ;;
            2|n|N|no|NO|"") printf 'Build files retained at %s\n' "$cwd"; return 0 ;;
            *) printf 'Enter y or n.\n' >&2 ;;
        esac
    done
}

# Exit function
exit_fn() {
    echo
    log "Build process completed."
    log "Make sure to star the repository to show your support: https://github.com/slyfox1186/script-repo"
}

# Download and extract source code
download_and_extract() {
    # Create build directory
    cwd=$(gnu_new_workdir)
    mkdir -p "$cwd"
    cd "$cwd" || exit 1

    # Extract source code
    if gnu_wget --show-progress -cqO "$archive_name" "$archive_url"; then
        tar -jxf "$archive_name" --strip-components 1
    else
        fail "Failed to download the parallel tar file 'parallel-latest.tar.bz2'."
    fi
}

# Build and install
build_and_install() {
    # Build process
    ./configure --prefix="$install_dir"
    make "-j$gnu_jobs"
    sudo make install

    # Create symbolic links
    sudo ln -sf "$install_dir/bin/parallel" "/usr/local/bin/parallel"
    sudo ln -sf "$install_dir/share/man/man1/parallel.1" "/usr/local/share/man/man1/parallel.1"
}

# Main script
main() {
    parse_arguments "$@"
    [[ "$version" == latest || "$version" =~ ^[0-9]{8}$ ]] || fail "Version must be latest or an eight-digit release date."
    archive_name="parallel-$version.tar.bz2"
    archive_url="https://ftp.gnu.org/gnu/parallel/$archive_name"
    install_dir="/usr/local/programs/parallel-$version"
    verify_not_root
    check_dependencies
    set_compiler_settings
    log "Building GNU parallel from source."
    echo
    download_and_extract
    build_and_install
    cleanup
    exit_fn
}

# Variables
version=latest
archive_name=""
archive_url="https://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2"
cwd="$PWD/parallel-build-script"
install_dir="/usr/local/programs/parallel-latest"


main "$@"
