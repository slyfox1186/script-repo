#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-emacs
##  Purpose: Build GNU Emacs from source
##  Updated: 03.18.2024 09:20:00 PM
##  Script version: 2.0

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
SCRIPT_VER="2.0"
PROGRAM="emacs"
VERSION="29.1"
ARCHIVE_DIR="${PROGRAM}-${VERSION}"
ARCHIVE_URL="https://ftp.gnu.org/gnu/${PROGRAM}/${ARCHIVE_DIR}.tar.xz"
ARCHIVE_EXT="${ARCHIVE_URL##*.}"
ARCHIVE_NAME="${ARCHIVE_DIR}.tar.${ARCHIVE_EXT}"
CWD="${PWD}/${PROGRAM}-build-script"
INSTALL_DIR="/usr/local/${PROGRAM}-${VERSION}"

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
    echo " -p    Specify installation prefix (default: ${INSTALL_DIR})"
    echo " -V    Enable verbose logging"
    echo " -h    Display this help message"
}

parse_arguments() {
    while getopts ":v:p:Vh" opt; do
        case $opt in
            v) VERSION="$OPTARG" ;;
            p) INSTALL_DIR="$OPTARG" ;;
            V) VERBOSE=1 ;;
            h) usage; exit 0 ;;
            \?) fail "Invalid option: $OPTARG" ;;
            :) fail "Option -$OPTARG requires an argument." ;;
        esac
    done
}

set_env_vars() {
    log "Setting environment variables..."
    export CC="ccache gcc"
    export CXX="ccache g++"
    export CFLAGS="-O3 -pipe -fno-plt -march=native"
    export CXXFLAGS="-O3 -pipe -fno-plt -march=native"
    export CPPFLAGS="-D_FORTIFY_SOURCE=2"
    export LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,${INSTALL_DIR}/lib"
    export PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    export PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/lib64/pkgconfig:/lib/pkgconfig"
}

check_dependencies() {
    log "Checking dependencies..."
    local pkg_mgr

    if command -v apt-get &>/dev/null; then
        pkg_mgr="apt-get"
    elif command -v dnf &>/dev/null; then
        pkg_mgr="dnf"
    elif command -v yum &>/dev/null; then
        pkg_mgr="yum"
    else
        fail "Unsupported package manager. Please install the required dependencies manually."
    fi

    local pkgs=(
        autoconf autoconf-archive autogen automake binutils build-essential ccache
        curl git guile-3.0-dev libdmalloc-dev libdmalloc5 libmpfr-dev libreadline-dev
        libtool libtool-bin libgif-dev lzip m4 nasm ninja-build texinfo zlib1g-dev yasm
    )

    local missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -ne 0 ]]; then
        warn "The following dependencies are missing: ${missing_pkgs[*]}"
        log "Installing missing dependencies..."
        sudo "$pkg_mgr" install -y "${missing_pkgs[@]}"
    fi
}

cleanup() {
    local choice

    echo
    echo "============================================"
    echo "  Do you want to clean up the build files?  "
    echo "============================================"
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p 'Your choice (1 or 2): ' choice

    case "$choice" in
        1) sudo rm -rf "$CWD" ;;
        2) ;;
        *) unset choice; cleanup ;;
    esac
}

build_emacs() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi

    [[ -d "$CWD" ]] && sudo rm -rf "$CWD"
    mkdir -p "$CWD"

    set_env_vars
    check_dependencies

    if [[ ! -f "$CWD/$ARCHIVE_NAME" ]]; then
        log "Downloading $ARCHIVE_NAME..."
        curl -Lso "$CWD/$ARCHIVE_NAME" "$ARCHIVE_URL"
    fi

    [[ -d "$CWD/$ARCHIVE_DIR" ]] && sudo rm -rf "$CWD/$ARCHIVE_DIR"
    mkdir -p "$CWD/$ARCHIVE_DIR/build"

    if ! tar -xf "$CWD/$ARCHIVE_NAME" -C "$CWD/$ARCHIVE_DIR" --strip-components 1; then
        fail "Failed to extract: $CWD/$ARCHIVE_NAME"
    fi

    cd "$CWD/$ARCHIVE_DIR" || exit 1
    sed -i 's/-DPROFILING=1 -pg/-DPROFILING=0 -pg/g' configure.ac
    autoreconf -fi

    cd build || exit 1
    ../configure --prefix="$INSTALL_DIR"

    if ! make "-j$(nproc --all)"; then
        fail "Failed to execute: make -j$(nproc --all). Line: $LINENO"
    fi

    if ! sudo make install; then
        fail "Failed to execute: sudo make install. Line: $LINENO"
    fi

    log "$PROGRAM $VERSION has been installed to $INSTALL_DIR"
}

link_binaries() {
    log "Linking $PROGRAM binaries to /usr/local/bin..."
    for file in "${INSTALL_DIR}/bin/"*; do
        local binary="${file##*/}"
        sudo ln -sf "$file" "/usr/local/bin/$binary"
    done
}

parse_arguments "$@"
build_emacs
link_binaries

log "Installation completed successfully."

cleanup

log "Make sure to star this repository to show your support!"
log "https://github.com/slyfox1186/script-repo"
