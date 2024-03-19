#!/usr/bin/env bash

# Purpose: Build GNU Parallel from source code
# Updated: 03.16.24
# Script version: 2.1
# Optimizations: Efficiency, readability, functionality, error handling, best practices

set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Log functions
log() { echo -e "${GREEN}[INFO] Bash${NC} $*"; }
warn() { echo -e "${YELLOW}[WARNING] Bash${NC} $*"; }
fail() {
    echo -e "${RED}[ERROR] Bash${NC} $*"
    exit 1
}

# Verify the script is not run as root
if [[ "$EUID" -eq 0 ]]; then
    fail "Do not run this script as root. Use sudo for necessary commands."
fi

# Dependencies
DEPENDENCIES=(
    autoconf autoconf-archive autogen automake binutils bison
    build-essential bzip2 ccache curl libc6-dev libpth-dev
    libtool libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev
    yasm
)

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
        sudo apt-get update
        sudo apt-get install -y "${missing_deps[@]}"
    else
        log "All dependencies are satisfied."
    fi
}

# Variables
PROGRAM_NAME="parallel"
DOWNLOAD_VERSION="latest"
INSTALL_DIR_VERSION="20240222"
ARCHIVE_URL="https://ftp.gnu.org/gnu/parallel/${PROGRAM_NAME}-${DOWNLOAD_VERSION}.tar.bz2"
CWD="$PWD/${PROGRAM_NAME}-build-script"
INSTALL_DIR="/usr/local/${PROGRAM_NAME}-${INSTALL_DIR_VERSION}"

# Cleanup function
cleanup() {
    echo
    read -r -p "Do you want to clean up the build files? [y/N] " choice
    case "$choice" in
        [yY]*|"") rm -fr "$CWD"; echo; log "Cleanup completed." ;;
        * ) log "Cleanup skipped." ;;
    esac
}

# Exit function
exit_fn() {
    echo
    log "Build process completed."
    log "Make sure to star the repository to show your support: https://github.com/slyfox1186/script-repo"
}

# Main script
main() {
    check_dependencies
    log "Building GNU ${PROGRAM_NAME} from source."
    echo

    # Create build directory
    mkdir -p "$CWD"
    cd "$CWD" || exit 1

    # Download and extract source
    curl -sSfLo "${PROGRAM_NAME}.tar.bz2" "$ARCHIVE_URL"
    tar -jxf "${PROGRAM_NAME}.tar.bz2" --strip-components 1

    # Build process
    ./configure --prefix="$INSTALL_DIR"
    make "-j$(nproc)"
    sudo make install

    # Create symbolic links
    find "$INSTALL_DIR/bin" -type f -exec sudo ln -s {} /usr/local/bin \;

    cleanup
    exit_fn
}

main "$@"
