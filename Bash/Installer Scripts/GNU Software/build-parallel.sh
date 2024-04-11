#!/usr/bin/env bash

# Purpose: Build GNU Parallel from source code
# Updated: 04.04.24
# Script version: 2.6
# Optimizations: Efficiency, readability, functionality, error handling, best practices

set -euo pipefail

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
                DOWNLOAD_VERSION="$2"
                shift 2
                ;;
            -l|--latest)
                DOWNLOAD_VERSION="latest"
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

# Verify the script is not run as root
verify_not_root() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must not run this script as root or with sudo."
    fi
}

# Check and install missing dependencies
check_dependencies() {
    local missing_deps=()
    for dep in "${DEPENDENCIES[@]}"; do
        if ! dpkg -l "$dep" &>/dev/null; then
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
        log_msg "Build directory removed."
        ;;
        [nN]*) ;;
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
    if [[ "$DOWNLOAD_VERSION" == "latest" ]]; then
        ARCHIVE_URL="https://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2"
    else
        ARCHIVE_URL="https://ftp.gnu.org/gnu/parallel/parallel-$DOWNLOAD_VERSION.tar.bz2"
    fi

    curl --connect-timeout 2 --retry 2 -LSso "$PROGRAM_NAME-$DOWNLOAD_VERSION.tar.bz2" "$ARCHIVE_URL"
 
    # Extract source code
    tar -jxf "$PROGRAM_NAME-$DOWNLOAD_VERSION.tar.bz2" --strip-components 1
}

# Build and install
build_and_install() {
    # Build process
    ./configure --prefix="$INSTALL_DIR"
    make "-j$(nproc --all)"
    sudo make install

    # Create symbolic links
    sudo ln -sf "$INSTALL_DIR/bin/parallel" "/usr/local/bin/parallel"
    sudo ln -sf "$INSTALL_DIR/share/man/man1/parallel.1" "/usr/local/share/man/man1/parallel.1"
}

# Main script
main() {
    parse_arguments "$@"
    verify_not_root
    check_dependencies
    log "Building GNU $PROGRAM_NAME from source."
    echo
    download_and_extract
    build_and_install
    cleanup
    exit_fn
}

# Variables
PROGRAM_NAME="parallel"
[[ -z ${DOWNLOAD_VERSION+x} ]] && DOWNLOAD_VERSION="20240322"
ARCHIVE_URL="https://ftp.gnu.org/gnu/parallel/$PROGRAM_NAME-$DOWNLOAD_VERSION.tar.bz2"
cwd="$PWD/$PROGRAM_NAME-build-script"
INSTALL_DIR="/usr/local/$PROGRAM_NAME-$DOWNLOAD_VERSION"
CLEANUP="false"

# Dependencies
DEPENDENCIES=(
    autoconf autoconf-archive autogen automake binutils bison
    build-essential bzip2 ccache curl libc6-dev libpth-dev
    libtool libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev
    yasm
)

main "$@"
