#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-texinfo.sh
##  Purpose: build gnu texinfo
##  Updated: 03.19.24
##  Script version: 1.3

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Set variables
script_ver="1.3"
archive_dir="texinfo-7.1"
archive_url="https://ftp.gnu.org/gnu/texinfo/$archive_dir.tar.xz"
archive_name="$archive_dir.tar.${archive_url##*.}"
cwd="$PWD/texinfo-build-script"
install_dir="/usr/local/$archive_dir"
web_repo="https://github.com/slyfox1186/script-repo"

# Create logging functions
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

fail() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "To report a bug, create an issue at: $web_repo/issues"
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
    log "Texinfo build script version $script_ver"
    echo "==============================================="
    echo
}

# Set compiler and optimization flags
set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-g -O3 -pipe -fno-plt -march=native"
    CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

# Set the path variables
set_path_variables() {
    PATH="/usr/lib/ccache:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export PKG_CONFIG_PATH PATH
}

# Show exit message
exit_fn() {
    echo
    log "Make sure to star this repository to show your support!"
    log "$web_repo"
    exit 0
}

# Prompt user to clean up files
cleanup() {
    local choice

    echo
    echo -e "${GREEN}============================================${NC}"
    echo -e "  ${YELLOW}Do you want to clean up the build files?${NC}  "
    echo -e "${GREEN}============================================${NC}"
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choice (1 or 2): " choice

    case "$choice" in
        1) rm -fr "$cwd";;
        2) ;;
        *) unset choice
           cleanup
           ;;
    esac
}

# Install required apt packages
install_dependencies() {
    pkgs=(autoconf automake curl build-essential libtool libtool-bin m4 tar xz-utils)
    missing_pkgs=""
    for pkg in ${pkgs[@]}; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            missing_pkgs+=" $pkg"
        fi
    done
    if [[ -n "$missing_pkgs" ]]; then
        sudo apt-get update
        sudo apt-get install $missing_pkgs
    fi
}

# Download the archive file
download_archive() {
    if [[ ! -f "$cwd/$archive_name" ]]; then
        curl -Lso "$cwd/$archive_name" "$archive_url"
    fi
}

# Extract archive files
extract_archive() {
    if ! tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1; then
        fail "Failed to extract: $cwd/$archive_name"
    fi
}

# Build program from source
build_program() {
    cd "$cwd/$archive_dir" || fail "Failed to change directory to: $cwd/$archive_dir"
    set_compiler_flags
    set_path_variables
    autoreconf -fi
    mkdir -p build && cd build
    ../configure --prefix="$install_dir" \
                 --disable-nls \
                 --enable-perl-xs \
                 --enable-threads=posix
    make "-j$(nproc --all)" || fail "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
    if ! sudo make install; then
        fail "Failed to execute: sudo make install. Line: ${LINENO}"
    fi
}

# Create soft links
create_soft_links() {
    sudo ln -sf "$install_dir"/bin/* /usr/local/bin/
}

# Main script
main() {
    check_root
    display_info
    install_dependencies
    [[ -d "$cwd/$archive_dir" ]] && rm -fr "$cwd/$archive_dir"
    mkdir -p "$cwd/$archive_dir"
    download_archive
    extract_archive
    build_program
    create_soft_links
    cleanup
    exit_fn
}

# Parse command line arguments
while getopts ":hndpst" opt; do
    case "$opt" in
        h|--help) echo "Usage: $0 [OPTIONS]"
           echo "  -h      Show this help message and exit"
           echo "  -d      Disable building with dmalloc"
           echo "  -s      Enable building shared libraries"
           shift
           exit 0
           ;;
        d) dmalloc_opt="--without-dmalloc" ;;
        s) shared_opt="--enable-shared" ;;
        \?) echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

main "$@"
