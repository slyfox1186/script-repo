#!/usr/bin/env bash

# Purpose: Build GNU Parallel from source code
# Updated: 06.01.24
# Script version: 2.7

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
        build-essential bzip2 ccache libc6-dev libpth-dev
        libtool libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev
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
    local choice
    echo
    read -p "Remove temporary build directory '$cwd'? [y/N] " response
    case "$response" in
        [yY]*|"")
            sudo rm -rf "$cwd"
            log "Build directory removed."
            ;;
        [nN]*)
            ;;
    esac
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
    mkdir -p "$cwd"
    cd "$cwd" || exit 1

    # Download the source code files
    if [[ "$version" == "latest" ]]; then
        archive_url="http://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2"
    fi

    # Extract source code
    if wget --show-progress -cqO "parallel-latest.tar.bz2" "http://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2"; then
        tar -jxf "parallel-latest.tar.bz2" --strip-components 1
    else
        fail "Failed to download the parallel tar file 'parallel-latest.tar.bz2'."
    fi
}

# Build and install
build_and_install() {
    # Build process
    ./configure --prefix="$install_dir"
    make "-j$(nproc --all)"
    sudo make install

    # Create symbolic links
    sudo ln -sf "$install_dir/bin/parallel" "/usr/local/bin/parallel"
    sudo ln -sf "$install_dir/share/man/man1/parallel.1" "/usr/local/share/man/man1/parallel.1"
}

# Main script
main() {
    log "Building the latest parallel..."
    parse_arguments "$@"
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
prog_name="parallel"
archive_url="https://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2"
cwd="$PWD/parallel-build-script"
install_dir="/usr/local/programs/parallel-latest"
CLEANUP="false"

[[ -d "$install_dir" ]] && sudo rm -fr "$install_dir"

main "$@"
