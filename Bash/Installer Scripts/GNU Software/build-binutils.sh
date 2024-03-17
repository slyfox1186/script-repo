#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-binutils
##  Purpose: build gnu binutils with GOLD enabled
##  Updated: 03.08.24
##  Script version: 1.1
##  To create softlinks in the /usr/local/bin folder pass the argument -l to the script.

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Default Values
PROGRAM="binutils"
VERSION="2.39"
PREFIX="/usr/local/$PROGRAM-$VERSION"
BUILD_DIR="/tmp/${PROGRAM}_build"
LOG_FILE="/tmp/${PROGRAM}_install.log"
VERBOSE=0
LINK=0
TEMP_DIR="/tmp/${PROGRAM}_temp"

usage() {
    echo -e "${GREEN}Usage:${NC} $0 [-v version] [-p prefix] [-l] [-V] [-L log_file] [-h]"
    echo "    -v    Specify $PROGRAM version (default: $VERSION)"
    echo "    -p    Specify installation prefix (default: $PREFIX)"
    echo "    -l    Link binaries to /usr/local/bin"
    echo "    -V    Enable verbose logging"
    echo "    -L    Specify log file path (default: $LOG_FILE)"
    echo "    -h    Display this help message"
}

log() {
    local level="$1"
    local message="$2"
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    case "$level" in
        INFO)
            echo -e "${timestamp} [${GREEN}INFO${NC}] ${message}" | tee -a "$LOG_FILE"
            [[ $VERBOSE -eq 1 ]] && echo -e "${timestamp} [${GREEN}INFO${NC}] ${message}"
            ;;
        WARN)
            echo -e "${timestamp} [${YELLOW}WARN${NC}] ${message}" | tee -a "$LOG_FILE"
            [[ $VERBOSE -eq 1 ]] && echo -e "${timestamp} [${YELLOW}WARN${NC}] ${message}"
            ;;
        ERROR)
            echo -e "${timestamp} [${RED}ERROR${NC}] ${message}" | tee -a "$LOG_FILE"
            [[ $VERBOSE -eq 1 ]] && echo -e "${timestamp} [${RED}ERROR${NC}] ${message}"
            ;;
    esac
}

parse_arguments() {
    while getopts ":v:p:lVL:h" opt; do
        case ${opt} in
            v ) VERSION="$OPTARG" ;;
            p ) PREFIX="/usr/local/$PROGRAM-$OPTARG" ;;
            l ) LINK=1 ;;
            V ) VERBOSE=1 ;;
            L ) LOG_FILE="$OPTARG" ;;
            h ) usage; exit 0 ;;
            \? ) log "ERROR" "Invalid option: $OPTARG"; usage; exit 1 ;;
            : ) log "ERROR" "Option -$OPTARG requires an argument."; usage; exit 1 ;;
        esac
    done
}

check_dependencies() {
    log "INFO" "Checking dependencies..."
    local deps=(wget tar make gcc)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "ERROR" "Dependency not found: $dep"
            exit 1
        fi
    done
}

install_autoconf() {
    local ac_ver=$(autoconf --version 2>/dev/null | head -n1 | awk '{print $NF}')
    if [[ "$ac_ver" != "2.69" ]]; then
        log "INFO" "Installing autoconf 2.69..."

        mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR"
        wget -nc -qO- "https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz" | tar xz
        cd autoconf-2.69
        ./configure --prefix="$TEMP_DIR/autoconf"
        make -j$(nproc)
        make install
        export PATH="$TEMP_DIR/autoconf/bin:$PATH"

        log "INFO" "Autoconf 2.69 installed."
    else
        log "INFO" "Autoconf 2.69 is already installed."
    fi
}

optimize_build() {
    OS=$(uname -s)
    ARCH=$(uname -m)
    log "INFO" "Detected OS: $OS, Architecture: $ARCH"

    case "$ARCH" in
        x86_64)
            TARGET="x86_64-elf"
            ;;
        aarch64)
            TARGET="aarch64-elf"
            ;;
        *)
            log "ERROR" "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    export CFLAGS="-O3 -march=native"
}

cleanup() {
    [[ $VERBOSE -eq 1 ]] && read -p "Remove build directory $BUILD_DIR? [Y/n] " -n 1 -r
    [[ $VERBOSE -eq 1 ]] && echo
    [[ $VERBOSE -eq 0 || $REPLY =~ ^[Yy]$ ]] && rm -rf "$BUILD_DIR"
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

exit_fn() { cleanup; exit $1; }

install_binutils() {
    check_dependencies
    install_autoconf
    optimize_build

    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"

    if [[ ! -f "$PROGRAM-$VERSION.tar.xz" ]]; then
        log "INFO" "Downloading $PROGRAM-$VERSION.tar.xz..."
        wget --show-progress -qc "https://ftp.gnu.org/gnu/$PROGRAM/$PROGRAM-$VERSION.tar.xz"
    fi

    tar xf "$PROGRAM-$VERSION.tar.xz"

    mkdir -p build && cd build

    log "INFO" "Configuring $PROGRAM for $TARGET..."
    "../$PROGRAM-$VERSION/configure" --target="$TARGET" --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror \
        --enable-gold --enable-plugins --enable-lto --enable-threads --enable-64-bit-bfd

    log "INFO" "Building $PROGRAM for $TARGET..."
    make -j$(nproc)

    log "INFO" "Installing $PROGRAM for $TARGET..."
    sudo make install

    log "INFO" "$PROGRAM $VERSION for $TARGET installed to $PREFIX."

    cd ../..
}

link_binutils() {
    log "INFO" "Linking $PROGRAM binaries to /usr/local/bin..."
    for file in "$PREFIX/bin/$TARGET-"*; do
        local binary=$(basename "$file")
        local trimmed_binary=${binary#$TARGET-}
        sudo ln -sf "$file" "/usr/local/bin/$trimmed_binary"
    done
}

parse_arguments "$@"
install_binutils
[[ $LINK -eq 1 ]] && link_binutils

log "INFO" "Installation completed successfully."

read -p "Do you want to remove the build directory $BUILD_DIR? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$BUILD_DIR"
    log "INFO" "Build directory removed."
else
    log "INFO" "Build directory not removed."
fi

exit_fn 0