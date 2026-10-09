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

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/installer-scripts/gnu-software/build-which.sh
##  Purpose: build gnu which
##  Updated: 03.19.24
##  Script version: 1.1

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set variables
script_ver="1.1"
archive_dir="which-2.21"
archive_url="https://ftp.gnu.org/gnu/which/$archive_dir.tar.gz"
archive_name="$archive_dir.tar.${archive_url##*.}"
cwd="$PWD/which-build-script"
install_dir="/usr/local/programs/$archive_dir"

# Create logging functions
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

fail() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Check if running as root or with sudo
check_root() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi
}

# Display script information
display_info() {
    log "Which build script version $script_ver"
    echo "==============================================="
    echo
}

# Set compiler and optimization flags
set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -fno-plt -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

# Set the path variables
set_path_variables() {
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export PKG_CONFIG_PATH PATH
}

# Show exit message
exit_fn() {
    echo
    log "Make sure to star this repository to show your support!"
    log "https://github.com/slyfox1186/script-repo"
    exit 0
}

# Prompt user to clean up files
cleanup_fn() {
    local response
    while true; do
        if ! read -r -p "Remove build directory '$cwd'? [y/N] " response; then
            printf '\nBuild files retained at %s\n' "$cwd"
            return 0
        fi
        case "$response" in
            1|y|Y|yes|YES) rm -rf -- "$cwd"; return 0 ;;
            2|n|N|no|NO|"") printf 'Build files retained at %s\n' "$cwd"; return 0 ;;
            *) printf 'Enter y or n.\n' >&2 ;;
        esac
    done
}

# Install required apt packages
install_dependencies() {
    pkgs=(automake gcc make curl tar)
    missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done
    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        sudo apt-get update
        sudo apt-get install "${missing_pkgs[@]}"
    fi
}

# Download and install autoconf 2.69

# Download the archive file
download_archive() {
    if [[ ! -f "$cwd/$archive_name" ]]; then
        gnu_curl -Lso "$cwd/$archive_name" "$archive_url"
    fi
}

# Extract archive files
extract_archive() {
    if ! tar -zxf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
        fail "Failed to extract: $cwd/$archive_name"
    fi
}

# Build program from source
build_program() {
    cd "$cwd/$archive_dir" || fail "Failed to change directory to: $cwd/$archive_dir"
    set_compiler_flags
    set_path_variables
    echo
    log "Building which..."
    echo

    cd build || exit 1
    ../configure --prefix="$install_dir" ${silent_rules:+"$silent_rules"}
    make "-j$gnu_jobs" || fail "Failed to execute: make -j$gnu_jobs. Line: ${LINENO}"
    if ! sudo make install; then
        fail "Failed to execute: sudo make install. Line: ${LINENO}"
    fi
}

# Create soft links
create_soft_links() {
    for file in "$install_dir"/bin/*; do
        [[ -e "$file" || -L "$file" ]] || continue
        sudo mkdir -p /usr/local/bin/
        sudo ln -sfn -- "$file" /usr/local/bin/
    done
}

# Display help menu
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Build and install the GNU Which program from source."
    echo
    echo "Options:"
    echo "  -h, --help       Display this help menu and exit"
    echo "  -s, --silent     Enable silent rules during the build process"
    echo "  -c, --cleanup    Clean up the build files after installation"
    echo
    echo "Examples:"
    echo "  $0                  Build and install GNU Which with default options"
    echo "  $0 -s               Build and install GNU Which with silent rules enabled"
    echo "  $0 -c               Clean up the build files after installation"
    echo
    echo "Note:"
    echo "  This script requires root or sudo access to install packages and the compiled program."
    echo "  The compiled program will be installed in $install_dir"
    echo "  Soft links will be created in /usr/local/bin for easy access to the program."
    echo
    echo "Report bugs to: https://github.com/slyfox1186/script-repo/issues"
    exit 0
}

# Parse command line options
parse_options() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                display_help
                ;;
            -s|--silent)
                silent_rules="--enable-silent-rules"
                ;;
            -c|--cleanup)
                cleanup="true"
                ;;
            *)
                echo "Invalid option: $1"
                exit 1
                ;;
        esac
        shift
    done
}

# Main script
main() {
    parse_options "$@"
    check_root
    display_info
    install_dependencies

    cwd=$(gnu_new_workdir)
    mkdir -p "$cwd/$archive_dir/build"
    download_archive
    extract_archive
    build_program
    create_soft_links
    if [[ "$cleanup" == "true" ]]; then
        cleanup_fn
    fi
    exit_fn
}

main "$@"
