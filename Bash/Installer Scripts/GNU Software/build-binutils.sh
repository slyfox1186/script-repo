#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-binutils.sh
##  Purpose: build gnu binutils with GOLD enabled
##  Updated: 03.18.2024 09:05:15 PM
##  Script version: 2.0
##  To create softlinks in the /usr/local/bin folder pass the argument -l to the script.

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default Values
PROGRAM="binutils"
VERSION="2.39"
PREFIX="/usr/local/${PROGRAM}-${VERSION}"
BUILD_DIR="/tmp/${PROGRAM}_build"
LOG_FILE="/tmp/${PROGRAM}_install.log"
VERBOSE=0
LINK=0
TEMP_DIR="/tmp/${PROGRAM}_temp"

fail() {
    echo -e "${RED}[FAIL] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}" | tee -a "$LOG_FILE"
}

log() {
    echo -e "${GREEN}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

debug() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo -e "${BLUE}[DEBUG] $1${NC}" | tee -a "$LOG_FILE"
    fi
}

usage() {
    echo -e "${GREEN}Usage:${NC} $0 [OPTIONS]"
    echo " -v    Specify ${PROGRAM} version (default: ${VERSION})"
    echo " -p    Specify installation prefix (default: ${PREFIX})"
    echo " -l    Link binaries to /usr/local/bin"
    echo " -V    Enable verbose logging"
    echo " -h    Display this help message"
}

parse_arguments() {
    while getopts ":v:p:lVh" opt; do
        case $opt in
            v ) VERSION="$OPTARG" ;;
            p ) PREFIX="/usr/local/${PROGRAM}-${OPTARG}" ;;
            l ) LINK=1 ;;
            V ) VERBOSE=1 ;;
            h ) usage; exit 0 ;;
            \? ) fail "Invalid option: $OPTARG" ;;
            : ) fail "Option -$OPTARG requires an argument." ;;
        esac
    done
}

check_dependencies() {
    log "Checking dependencies..."
    local deps=(wget tar make gcc)
    local pkg_mgr

    if command -v apt-get >/dev/null; then
        pkg_mgr="apt-get"
    elif command -v dnf >/dev/null; then
        pkg_mgr="dnf"
    elif command -v yum >/dev/null; then
        pkg_mgr="yum"
    else
        fail "Unsupported package manager. Please install the required dependencies manually."
    fi

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            warn "Dependency not found: $dep. Installing..."
            sudo "$pkg_mgr" install -y "$dep" || fail "Failed to install $dep."
        fi
    done
}

install_autoconf() {
    local ac_ver=$(autoconf --version 2>/dev/null | head -n1 | awk '{print $NF}')
    if [[ "$ac_ver" != "2.69" ]]; then
        log "Installing autoconf 2.69..."
        wget -nc -qO- "https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz" | tar xz -C "$TEMP_DIR"
        cd "$TEMP_DIR/autoconf-2.69"
        ./configure --prefix="$TEMP_DIR/autoconf"
        make "-j$(nproc --all)"
        make install
        export PATH="$TEMP_DIR/autoconf/bin:$PATH"
        log "Autoconf 2.69 installed."
    else
        log "Autoconf 2.69 is already installed."
    fi
}

optimize_build() {
    OS=$(uname -s)
    ARCH=$(uname -m)
    debug "Detected OS: $OS, Architecture: $ARCH"

    case "$ARCH" in
        x86_64)  TARGET="x86_64-elf" ;;
        aarch64) TARGET="aarch64-elf" ;;
        *)       fail "Unsupported architecture: $ARCH" ;;
    esac

    CC="gcc"
    CXX="g++"
    CFLAGS="-g -O3 -pipe -fno-plt -march=native"
    CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
    export CC CFLAGS CXX CXXFLAGS
}

cleanup() {
    if [[ $VERBOSE -eq 1 ]]; then
        read -p "Remove build directory $BUILD_DIR? [Y/n] " -n 1 -r
        echo
    fi
    [[ $VERBOSE -eq 0 || $REPLY =~ ^[Yy]$ ]] && rm -rf "$BUILD_DIR"
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

install_binutils() {
    check_dependencies
    install_autoconf
    optimize_build

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if [[ ! -f "${PROGRAM}-${VERSION}.tar.xz" ]]; then
        log "Downloading ${PROGRAM}-${VERSION}.tar.xz..."
        wget --show-progress -qc "https://ftp.gnu.org/gnu/${PROGRAM}/${PROGRAM}-${VERSION}.tar.xz"
    fi

    tar xf "${PROGRAM}-${VERSION}.tar.xz"
    cd "${PROGRAM}-${VERSION}"

    log "Configuring ${PROGRAM} for ${TARGET}..."
    ./configure --target="$TARGET" --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror \
        --enable-gold --enable-plugins --enable-lto --enable-threads --enable-64-bit-bfd

    log "Building ${PROGRAM} for ${TARGET}..."
    make "-j$(nproc --all)"

    log "Installing ${PROGRAM} for ${TARGET}..."
    sudo make install

    log "${PROGRAM} ${VERSION} for ${TARGET} installed to ${PREFIX}."
}

link_binutils() {
    log "Linking ${PROGRAM} binaries to /usr/local/bin..."
    for file in "${PREFIX}/bin/${TARGET}-"*; do
        local binary="${file##*/}"
        local trimmed_binary="${binary#"$TARGET"-}"
        sudo ln -sf "$file" "/usr/local/bin/$trimmed_binary"
    done
}

parse_arguments "$@"
install_binutils
[[ $LINK -eq 1 ]] && link_binutils

log "Installation completed successfully."

read -p "Do you want to remove the build directory $BUILD_DIR? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cleanup
    log "Build directory removed."
else
    log "Build directory not removed."
fi
