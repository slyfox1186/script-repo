#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-nano
##  Purpose: build gnu nano
##  Updated: 08.03.23
##  Script version: 2.0

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set variables
script_ver="1.1"
cwd="$PWD/tar-build-script"
gnu_ftp="https://ftp.gnu.org/gnu/tar/"

# Create logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Check if running as root or with sudo
check_root() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "This script must be run without root or sudo."
    fi
}

# Display script information
display_info() {
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}         Tar Install script - v$script_ver"
    echo -e "${GREEN}============================================${NC}"
    echo
}

# Set compiler and optimization flags
set_compiler_flags() {
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-O2 -pipe -fno-plt -march=native -mtune=native"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath,/usr/local/$archive_dir/lib"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS
}

# Install missing packages
install_dependencies() {
    log "Checking and installing missing packages..."
    pkgs="autoconf automake autopoint binutils gcc make curl tar xz-utils libintl-perl libintl-xs-perl"
    missing_pkgs=""
    for pkg in $pkgs; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            missing_pkgs+=" $pkg"
        fi
    done
    if [[ -n "$missing_pkgs" ]]; then
        sudo apt-get install $missing_pkgs
    fi
}

# Find the latest tar tarball
find_latest_tar_version() {
    log "Finding the latest release..."
    latest_tar_version=$(curl -fsS "$gnu_ftp" | grep -oP 'tar-\K[0-9]+\.[0-9]+\.tar\.xz' | sort -rV | head -n1)
    if [[ -z "$latest_tar_version" ]]; then
        fail "Failed to find the latest release."
    fi
    archive_url="${gnu_ftp}tar-$latest_tar_version"
    archive_name="tar-$latest_tar_version"
    archive_dir="tar-${latest_tar_version%.tar.xz}"
}

# Download and extract the archive
download_and_extract() {
    log "Downloading and extracting..."
    mkdir -p "$cwd/$archive_dir"
    wget --show-progress -cqO "$cwd/$archive_name" "$archive_url"
    tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1
}

# Build and install
build_and_install() {
    log "Building and installing..."
    echo
    cd "$cwd/$archive_dir"
    set_compiler_flags
    autoreconf -fi
    ./configure --prefix="/usr/local/$archive_dir" \
                --disable-nls \
                --enable-backup-scripts \
                --enable-gcc-warnings=no
    make "-j$(nproc --all)" || fail "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
    sudo make install || fail "Failed to execute: sudo make install. Line: ${LINENO}"
    echo
    log "Installation completed successfully."
}

# Create soft links
create_soft_links() {
    log "Creating soft links..."
    sudo ln -sf "/usr/local/$archive_dir/bin/tar" "/usr/local/bin/tar"
}

# Cleanup
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

# Main script
main() {
    check_root
    display_info
    install_dependencies
    find_latest_tar_version
    download_and_extract
    build_and_install
    echo
    create_soft_links
    echo
    cleanup
    echo
    log "Make sure to star this repository to show your support!"
    log "https://github.com/slyfox1186/script-repo"
}

main
