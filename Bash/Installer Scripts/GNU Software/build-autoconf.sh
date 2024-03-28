#!/usr/bin/env bash

# Build GNU Autoconf from source
# You can set the version of autoconf by executing the
# script like this: ./build-autoconf.sh --version 2.71

set -eo pipefail
trap 'echo "Error occurred at line: $LINENO"; exit 1' ERR

default_program_version="2.69" # Default version
program_name="autoconf"
install_prefix="/usr/local"
verbose=0
build_dir=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -v, --version VERSION    Specify the version of Autoconf to build (default: $default_program_version)"
    echo "  -h, --help               Show this help message"
    echo
    echo "Example:"
    echo "  $0 --version 2.71"
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                program_version="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    program_version="${program_version:-$default_program_version}"
    build_dir="/tmp/${program_name}-${program_version}-build"
}

# Simplify logging based on verbosity
log_msg() {
    if [[ $verbose -eq 1 ]]; then
        echo "$@"
    fi
}

# Install dependencies
install_deps() {
    log_msg "Installing dependencies..."
    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y autoconf-archive autogen automake autopoint autotools-dev binutils bison build-essential bzip2 ccache curl libtool libtool-bin lzip lzma-dev m4 nasm texinfo zlib1g-dev yasm
    elif command -v dnf &>/dev/null; then
        dnf install -y autoconf-archive autogen automake autopoint autotools-dev binutils bison bzip2 ccache curl libtool libtool-ltdl-devel lzip lzma-devel m4 nasm texinfo xz yasm zlib-devel
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm autoconf-archive autogen automake autopoint binutils bison bzip2 ccache curl libtool lzip lzma m4 nasm texinfo xz yasm zlib
    else
        echo "Unsupported package manager. Please install the required dependencies manually."
        exit 1
    fi
}

# Preparing build environment
prepare_build() {
    [[ -d "$build_dir" ]] && rm -rf "$build_dir"
    mkdir -p "$build_dir"
    log_msg "Preparing build directory at $build_dir"
}

# Download and extract source archive
download_and_extract() {
    local archive_url="https://ftp.gnu.org/gnu/autoconf/${program_name}-${program_version}.tar.xz"
    local archive_name="${program_name}-${program_version}.tar.xz"
    log_msg "Downloading $archive_url"
    curl -fsSL "$archive_url" -o "$build_dir/$archive_name"
    log_msg "Extracting archive..."
    tar -xf "$build_dir/$archive_name" -C "$build_dir" --strip-components 1
}

# Configure, build, and install
build_and_install() {
    cd "$build_dir"
    log_msg "Configuring build..."
    ./configure --prefix="$install_prefix/${program_name}-${program_version}"
    log_msg "Compiling..."
    make "-j$(nproc)"
    log_msg "Installing..."
    make install
}

# Create symlinks in a common bin directory
create_symlinks() {
    log_msg "Creating symlinks..."
    for file in "$install_prefix/${program_name}-${program_version}"/bin/*; do
        base_name=$(basename "$file" | sed 's/-[0-9].*$//') # Trim extra versioning if present
        ln -sfn "$file" "/usr/local/bin/$base_name"
    done
}

# Cleanup resources
cleanup() {
    read -rp "Remove temporary build directory '$build_dir'? [y/N] " response
    if [[ $response =~ ^[Yy]$ ]]; then
        rm -rf "$build_dir"
        log_msg "Build directory removed."
    fi
}

main() {
    parse_args "$@"
    if [[ "$EUID" -ne 0 ]]; then
        echo "This script must be run as root or with sudo."
        exit 1
    fi
    install_deps
    prepare_build
    download_and_extract
    build_and_install
    create_symlinks
    cleanup
    log_msg "Autoconf $program_version build completed successfully!"
    log_msg "https://github.com/slyfox1186/script-repo"
}

main "$@"
