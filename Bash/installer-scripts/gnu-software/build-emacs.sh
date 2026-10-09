#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Ee -o pipefail
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

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/installer-scripts/gnu-software/build-emacs
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
PROGRAM="emacs"
VERSION="29.1"
ARCHIVE_DIR="${PROGRAM}-${VERSION}"
ARCHIVE_URL="https://ftp.gnu.org/gnu/${PROGRAM}/${ARCHIVE_DIR}.tar.xz"
ARCHIVE_EXT="${ARCHIVE_URL##*.}"
ARCHIVE_NAME="${ARCHIVE_DIR}.tar.${ARCHIVE_EXT}"
CWD="${PWD}/${PROGRAM}-build-script"
INSTALL_DIR=""
LOG_FILE=/dev/null
VERBOSE=0

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
    echo " -p    Specify installation prefix (default: ${INSTALL_DIR:-/usr/local/programs/$PROGRAM-$VERSION})"
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
    CC="ccache gcc"
    CXX="ccache g++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,${INSTALL_DIR}/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS PKG_CONFIG_PATH PATH
}

check_dependencies() {
    log "Checking dependencies..."
    local pkg_mgr

    if command -v apt-get &>/dev/null; then
        pkg_mgr="apt-get"
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
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
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
    local response
    while true; do
        if ! read -r -p "Remove build directory '$CWD'? [y/N] " response; then
            printf '\nBuild files retained at %s\n' "$CWD"
            return 0
        fi
        case "$response" in
            1|y|Y|yes|YES) rm -rf -- "$CWD"; return 0 ;;
            2|n|N|no|NO|"") printf 'Build files retained at %s\n' "$CWD"; return 0 ;;
            *) printf 'Enter y or n.\n' >&2 ;;
        esac
    done
}

build_emacs() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi

    CWD=$(gnu_new_workdir)

    mkdir -p "$CWD"

    set_env_vars
    check_dependencies

    if [[ ! -f "$CWD/$ARCHIVE_NAME" ]]; then
        log "Downloading $ARCHIVE_NAME..."
        gnu_curl -Lso "$CWD/$ARCHIVE_NAME" "$ARCHIVE_URL"
    fi

    mkdir -p "$CWD/$ARCHIVE_DIR/build"

    if ! tar -xf "$CWD/$ARCHIVE_NAME" -C "$CWD/$ARCHIVE_DIR" --strip-components 1; then
        fail "Failed to extract: $CWD/$ARCHIVE_NAME"
    fi

    cd "$CWD/$ARCHIVE_DIR" || exit 1
    sed -i 's/-DPROFILING=1 -pg/-DPROFILING=0 -pg/g' configure.ac

    cd build || exit 1
    ../configure --prefix="$INSTALL_DIR"

    if ! make "-j$gnu_jobs"; then
        fail "Failed to execute: make -j$gnu_jobs. Line: $LINENO"
    fi

    if ! sudo make install; then
        fail "Failed to execute: sudo make install. Line: $LINENO"
    fi

    log "$PROGRAM $VERSION has been installed to $INSTALL_DIR"
}

link_binaries() {
    log "Linking $PROGRAM binaries to /usr/local/bin..."
    for file in "${INSTALL_DIR}/bin/"*; do
        [[ -e "$file" || -L "$file" ]] || continue
        local binary="${file##*/}"
        sudo ln -sf "$file" "/usr/local/bin/$binary"
    done
}

parse_arguments "$@"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "Invalid Emacs version: $VERSION"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/programs/$PROGRAM-$VERSION}"
[[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != / ]] || fail "Prefix must be an absolute directory other than /."
ARCHIVE_DIR="$PROGRAM-$VERSION"
ARCHIVE_URL="https://ftp.gnu.org/gnu/$PROGRAM/$ARCHIVE_DIR.tar.xz"
ARCHIVE_NAME="$ARCHIVE_DIR.tar.xz"
build_emacs
link_binaries

log "Installation completed successfully."

cleanup

log "Make sure to star this repository to show your support!"
log "https://github.com/slyfox1186/script-repo"
