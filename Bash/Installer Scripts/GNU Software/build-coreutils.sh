#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-coreutils.sh
##  Purpose: build gnu coreutils
##  Updated: 05.06.24
##  Script version: 1.3
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

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

# Function to install dependencies
install_dependencies() {
    log "Checking and installing necessary dependencies..."
    local -a missing_pkgs pkgs
    local pkg
    pkgs=(autoconf autoconf-archive build-essential libtool m4 wget)

    missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ "${#missing_pkgs[@]}" -gt 0 ]; then
        sudo apt update
        sudo apt install "${missing_pkgs[@]}"
    fi
}

# Dynamically determines and downloads the latest version of GNU Core Utilities
download_coreutils() {
    log "Fetching the latest version of GNU Core Utilities..."
    local version
    version=$(curl -fsS "https://ftp.gnu.org/gnu/coreutils/" | grep -oP 'coreutils-\K([0-9.]{3})' | sort -ruV | head -n1)
    if [[ -z "$version" ]]; then
        fail "Failed to fetch the latest version of GNU Core Utilities. Line: $LINENO"
    fi
    local tarball="coreutils-$version.tar.xz"
    local url="https://ftp.gnu.org/gnu/coreutils/$tarball"
    log "Downloading GNU Core Utilities version $version..."
    if wget --show-progress -cqO "$working/$tarball" "$url"; then
        mkdir -p "$working/coreutils-$version/build"
        tar -xf "$working/$tarball" -C "$working/coreutils-$version" --strip-components=1
        cd "$working/coreutils-$version" || fail "Failed to enter the coreutils directory. Line: $LINENO"
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
    install_dir="$install_dir-$version"
    ../configure --prefix="$install_dir" \
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
    sudo ln -sf "$install_dir/bin/"* "/usr/local/bin/"
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
    set_compiler_flags
    install_dependencies
    download_coreutils
    build_and_install
    link_coreutils
    cleanup
}

# Setup working directory and execute main function
cwd="$PWD"
working="$cwd/build-coreutils-script"

install_dir="/usr/local/coreutils"

set_deps=false
set_links=false
set_cleanup=false

mkdir -p "$working"; cd "$working" || exit 1

main "$@"
