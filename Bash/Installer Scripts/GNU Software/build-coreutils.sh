#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-coreutils.sh
##  Purpose: build gnu coreutils
##  Updated: 03.17.24
##  Script version: 1.2
##  Execution: ./build-coreutils.sh --help

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"

# Function to log messages
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Function to display warnings
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to handle failures
fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root or with sudo
check_root() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "This script must be run without root privileges."
    fi
}

# Function to display help menu
show_help() {
    echo "Usage: $0 [option]"
    echo "Options:"
    echo "  -h, --help            Show this help message."
    echo "  -d,                   Check for and install missing dependencies."
    echo "  -l,                   Link the installed binaries to /usr/local/bin."
    echo "  -c,                   Cleanup the build directory and its contents."
}

# Function to install dependencies
install_dependencies() {
    log "Checking and installing necessary dependencies..."
    local missing_packages=()
    for package in wget build-essential autoconf autoconf-archive; do
        if ! dpkg -l "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        if command -v apt-get >/dev/null; then
            apt-get update
            apt-get install -y "${missing_packages[@]}"
        else
            fail "Unsupported package manager. Please install dependencies manually. Line: $LINENO"
        fi
    else
        log "All dependencies are already installed."
    fi
}

# Dynamically determines and downloads the latest version of GNU Core Utilities
download_coreutils() {
    log "Fetching the latest version of GNU Core Utilities..."
    local latest_version
    latest_version=$(wget -qO- "https://ftp.gnu.org/gnu/coreutils/" | grep -oP 'coreutils-\K[0-9.]+(?=\.tar\.xz)' | sort -rV | head -n1)
    if [[ -z "$latest_version" ]]; then
        fail "Failed to fetch the latest version of GNU Core Utilities. Line: $LINENO"
    fi
    local tarball="coreutils-$latest_version.tar.xz"
    local url="https://ftp.gnu.org/gnu/coreutils/$tarball"
    log "Downloading GNU Core Utilities version $latest_version..."
    if wget --show-progress -cqO "$working/$tarball" "$url"; then
        mkdir -p "$working/coreutils-$latest_version/build"
        tar -xf "$working/$tarball" -C "$working/coreutils-$latest_version" --strip-components=1
        cd "$working/coreutils-$latest_version" || fail "Failed to enter the coreutils directory. Line: $LINENO"
    else
        fail "Failed to download GNU Core Utilities. Line: $LINENO"
    fi
}

# Configures, compiles, and installs the downloaded version of Core Utilities
build_and_install() {
    local systemd_switch
    log "Configuring, compiling, and installing GNU Core Utilities..."
    autoreconf -fi
    cd build || exit 1
    # Determine if systemd is running
    local test_systemd=$(stat /sbin/init | grep systemd)
    if [[ -n "$test_systemd" ]]; then
        systemd_switch="--enable-systemd"
    else
        systemd_switch="--disable-systemd"
    fi
    ../configure --prefix=/usr/local/coreutils \
                 --disable-nls --disable-year2038 \
                 --enable-gcc-warnings=no --enable-threads=posix \
                 --with-libiconv-prefix=/usr --with-openssl=auto "$systemd_switch" || (
                 fail "Configure script failed. Line: $LINENO"
             )
    make "-j$(nproc --all)" || fail "Failed to execute: make -j$(nproc --all). Line: $LINENO"
    sudo make install || fail "Failed to execute: make install. Line: $LINENO"
    log "GNU Core Utilities installed successfully."
}

# Links the installed binaries to a directory in the path
link_coreutils() {
    log "Linking installed binaries to /usr/local/bin..."
    if ! sudo ln -sf "/usr/local/coreutils/bin/"* "/usr/local/bin/"; then
        warn "Failed to link binaries."
    else
        log "Binaries linked successfully."
    fi
}

# Cleans up the build directory and its contents
cleanup() {
    log "Cleaning up the build directory and its contents..."
    if ! sudo rm -fr "$working"; then
        warn "Failed to clean up the build directory."
    else
        log "Cleanup completed successfully."
    fi
}

# Main logic flow
main() {
    check_root

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -d) set_deps=true ;;
            -l) set_links=true ;;
            -c) set_cleanup=true ;;
             *) show_help; exit 1 ;;
        esac
        shift
    done

    # If no specific option is provided, proceed with these actions
    if $set_deps; then
        install_dependencies
    fi

    download_coreutils
    build_and_install

    if $set_links; then
        link_coreutils
    fi

    if $set_cleanup; then
        cleanup
    fi
}

# Setup working directory and execute main function
cwd="$PWD"
working="$cwd/build-coreutils-script"

set_deps=false
set_links=false
set_cleanup=false

mkdir -p "$working"
cd "$working" || exit 1

main "$@"
