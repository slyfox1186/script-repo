#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-which.sh
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
install_dir="/usr/local/$archive_dir"
web_repo="https://github.com/slyfox1186/script-repo"
autoconf_url="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-autoconf-2.69.sh"

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
    log "Which build script version $script_ver"
    echo "==============================================="
    echo
}

# Set compiler and optimization flags
set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O3 -pipe -fno-plt -march=native"
    CXXFLAGS="-O3 -pipe -fno-plt -march=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-rpath,$install_dir/lib"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

# Set the path variables
set_path_variables() {
    PATH="/usr/lib/ccache:$cwd/working/bin:$HOME/perl5/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
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
cleanup_fn() {
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
           cleanup_fn
           ;;
    esac
}

# Install required apt packages
install_dependencies() {
    pkgs=(automake gcc make curl tar)
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

# Download and install autoconf 2.69
install_autoconf() {
    log "Downloading autoconf 2.69 script..."
    echo
    mkdir -p "$cwd/autoconf-2.69/build" "$cwd/working"
    curl -Lso "$cwd/autoconf-2.69.tar.xz" "https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz"
    tar -xf "$cwd/autoconf-2.69.tar.xz" -C "$cwd/autoconf-2.69" --strip-components 1
    cd "$cwd/autoconf-2.69" || exit 1
    autoreconf -fi
    cd build || exit 1
    ../configure --prefix="$cwd/working"
    make "-j$(nproc --all)"
    make install
}

# Download the archive file
download_archive() {
    if [[ ! -f "$cwd/$archive_name" ]]; then
        curl -Lso "$cwd/$archive_name" "$archive_url"
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
    autoupdate
    autoreconf -fi
    cd build || exit 1
    ../configure --prefix="$install_dir" --enable-silent-rules
    make "-j$(nproc --all)" || fail "Failed to execute: make -j$(nproc --all). Line: ${LINENO}"
    if ! sudo make install; then
        fail "Failed to execute: sudo make install. Line: ${LINENO}"
    fi
}

# Create soft links
create_soft_links() {
    sudo ln -sf "$install_dir"/bin/* /usr/local/bin/
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
    echo "Report bugs to: $web_repo/issues"
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
                display_help
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
    [[ -d "$cwd/$archive_dir" ]] && rm -fr "$cwd/$archive_dir"
    mkdir -p "$cwd/$archive_dir/build"
    install_autoconf
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