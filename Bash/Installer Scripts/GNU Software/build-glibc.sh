#!/usr/bin/env bash

# Github script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-glibc.sh
# Purpose: Build GNU glibc
# Updated: 03.16.24
# Script version: 3.0

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
archive_dir="glibc-2.39"
archive_url="https://ftp.gnu.org/gnu/glibc/$archive_dir.tar.xz"
archive_ext="${archive_url##*.}"
archive_name="$archive_dir.tar.$archive_ext"
working="/tmp/glibc-build-script"
install_dir="/usr/local/$archive_dir"
log_file="$working/build.log"

# Optimization flags
CPU_ARCH=$(lscpu | awk -F ': +' '/Architecture/ {print $NF}')
CPU_CORES=$(nproc --all)
CFLAGS="-O2 -march=$CPU_ARCH -mtune=native -pipe -fstack-protector-strong -fstack-clash-protection -fcf-protection"
CXXFLAGS="$CFLAGS"
LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,--hash-style=gnu -Wl,-z,relro,-z,now"

# Functions
fail() {
    mkdir -p "$(dirname "$log_file")"
    echo -e "${RED}[$(date +'%m.%d.%Y %T')] ERROR: $1${NC}" | tee -a "$log_file"
    echo -e "${RED}To report a bug create an issue at: https://github.com/slyfox1186/script-repo/issues${NC}" | tee -a "$log_file"
    exit 1
}

warn() {
    mkdir -p "$(dirname "$log_file")"
    echo -e "${YELLOW}[$(date +'%m.%d.%Y %T')] WARNING: $1${NC}" | tee -a "$log_file"
}

log() {
    mkdir -p "$(dirname "$log_file")"
    echo -e "${GREEN}[$(date +'%m.%d.%Y %T')] $1${NC}" | tee -a "$log_file"
}

cleanup() {
    log "Cleaning up build files..."
    rm -rf "$working"
}

show_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -c, --cleanup    Clean up build files after the build"
    echo "  -v, --verbose    Enable verbose logging"
    echo "  -s, --silent     Run the script silently (no output)"
}

create_symlinks() {
    log "Creating symbolic links..."
    for file in "$install_dir"/bin/*; do
        local filename
        filename=$(basename "$file")
        local linkname
        linkname=${filename#*-}
        ln -sf "$file" "/usr/local/bin/$linkname" || warn "Failed to create symlink for $filename"
    done
    
    ln -sf "$install_dir/lib"/* "/usr/local/lib"
    ln -sf "$install_dir/lib64"/* "/usr/local/lib64"
    ln -sf "$install_dir/share"/* "/usr/local/share"
}

detect_timezone() {
    local timezone_file="/etc/timezone"
    if [[ -f "$timezone_file" ]]; then
        local timezone
        timezone=$(cat "$timezone_file")
        echo "$timezone"
    else
        warn "Unable to detect the system's timezone. Defaulting to UTC."
        echo "UTC"
    fi
}

install_dependencies() {
    log "Checking dependencies..."
    local dependencies=("autoconf" "autoconf-archive" "autogen" "automake" "build-essential" "ccache" "cmake" "curl" "git" "libltdl-dev" "perl" "python3" "texinfo")
    local missing_deps=()

    for pkg in "${dependencies[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_deps+=("$pkg")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "Installing missing dependencies: ${missing_deps[*]}"
        if ! apt-get install -y "${missing_deps[@]}"; then
            fail "Failed to install dependencies."
        fi
    fi
}

download_archive() {
    log "Downloading $archive_url..."
    if ! curl -Lso "$working/$archive_name" "$archive_url"; then
        fail "Failed to download $archive_url."
    fi
}

extract_archive() {
    log "Extracting archive files..."
    if ! tar -xf "$working/$archive_name" -C "$working"; then
        fail "Failed to extract $working/$archive_name."
    fi
}

build_glibc() {
    log "Building glibc..."

    cd "$working/$archive_dir" || fail "Failed to change directory to $working/$archive_dir."

    autoreconf -fi

    mkdir -p build && cd build

    ../configure --prefix="$install_dir" \
                 --enable-stack-protector=strong \
                 --enable-stackguard-randomization \
                 --disable-werror \
                 --disable-debug \
                 --disable-nscd \
                 --without-selinux \
                 --enable-bind-now \
                 --enable-multi-arch \
                 --enable-static-pie \
                 --with-pic \
                 CFLAGS="$CFLAGS" \
                 CXXFLAGS="$CXXFLAGS" \
                 LDFLAGS="$LDFLAGS"

    if ! make "-j$CPU_CORES"; then
        fail "Failed to build glibc."
    fi

    if ! make "-j$CPU_CORES" check; then
        warn "Some tests failed during the glibc build process."
    fi
}

install_glibc() {
    log "Installing glibc..."
    if ! make "-j$CPU_CORES" install; then
        fail "Failed to install glibc."
    fi

    if ! make "-j$CPU_CORES" localedata/install-locales; then
        fail "Failed to install locale files."
    fi
}

update_system() {
    log "Updating time info..."
    local timezone
    timezone=$(detect_timezone)
    ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime

    log "Updating dynamic linker cache..."
    ldconfig
}

main() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--cleanup)
                cleanup_files=true
                ;;
            -v|--verbose)
                verbose=true
                ;;
            -s|--silent)
                silent=true
                ;;
            *)
                warn "Invalid argument: $1. Use -h or --help for usage information."
                ;;
        esac
        shift
    done

    # Check if running with root or sudo access
    if [[ "$EUID" -ne 0 ]]; then
        fail "This script must be run with root or sudo access."
    fi

    # Create output directory
    log "Creating output directory..."
    mkdir -p "$working"

    # Download archive file
    if [[ ! -f "$working/$archive_name" ]]; then
        download_archive
    else
        log "Archive file already exists: $working/$archive_name"
    fi

    # Extract archive files
    extract_archive

    # Install dependencies
    install_dependencies

    # Build glibc
    build_glibc

    # Install glibc
    install_glibc

    # Create symbolic links
    create_symlinks

    # Update system
    update_system

    # Clean up if requested
    if [[ "$cleanup_files" == true ]]; then
        cleanup
    fi

    log "glibc build completed successfully."
}

main "$@"
