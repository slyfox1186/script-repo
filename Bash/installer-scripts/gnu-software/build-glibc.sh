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

# Github script: https://github.com/slyfox1186/script-repo/blob/main/Bash/installer-scripts/gnu-software/build-glibc.sh
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
install_dir="/usr/local/programs/$archive_dir"
log_file=/dev/null
cleanup_files=false
verbose=false
silent=false

# Optimization flags
CPU_CORES=$gnu_jobs
CFLAGS="-O2 -march=native -mtune=native -pipe -fstack-protector-strong -fstack-clash-protection"
CXXFLAGS="$CFLAGS"
LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,--hash-style=gnu -Wl,-z,relro,-z,now"

# Functions
fail() {
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
    if [[ "$silent" == true ]]; then
        printf "%s\n" "$1" >> "$log_file"
    else
        echo -e "${GREEN}[$(date +'%m.%d.%Y %T')] $1${NC}" | tee -a "$log_file"
    fi
}

cleanup() {
    rm -rf -- "$working"
}

show_usage() {
    echo "Usage: $0 [options]"
    echo "Install glibc 2.39 into its isolated prefix: $install_dir"
    echo "The build must pass make check before installation."
    echo "Use the installed loader explicitly for programs that need this glibc."
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -c, --cleanup    Clean up build files after the build"
    echo "  -v, --verbose    Enable verbose logging"
    echo "  -s, --silent     Run the script silently (no output)"
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
    if ! gnu_curl -Lso "$working/$archive_name" "$archive_url"; then
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
        fail "glibc checks failed. Installation was stopped."
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
                fail "Invalid argument: $1. Use -h or --help for usage information."
                ;;
        esac
        shift
    done

    # Check if running with root or sudo access
    if [[ "$EUID" -ne 0 ]]; then
        fail "This script must be run with root or sudo access."
    fi

    # Create output directory
    working=$(gnu_new_workdir)
    log_file="$working/build.log"
    log "Creating output directory..."
    if [[ "$verbose" == true ]]; then
        log "Build directory: $working; jobs: $CPU_CORES; prefix: $install_dir"
    fi

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

    # Clean up if requested
    if [[ "$cleanup_files" == true ]]; then
        cleanup
        log_file=/dev/null
    fi

    log "glibc build completed successfully."
}

main "$@"
