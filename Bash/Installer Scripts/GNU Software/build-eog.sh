#!/usr/bin/env bash

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-eog
##  Purpose: build gnu eye of gnome (aka eog)
##  Updated: 08.31.23
##  Script version: 2.0

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Define global variables
script_ver=2.0
archive_dir=eog
archive_url="https://download.gnome.org/sources/eog/44/eog-44.3.tar.xz"
install_dir="/usr/local/programs/$archive_dir-44.3"
cwd="$PWD/$archive_dir-build-script"
log_file="$cwd/build.log"

# Function to display usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Build GNU Eye of GNOME (eog) from source code.

Options:
  -h, --help    Display this help message and exit
  -v, --version Display script version and exit
  -c, --clean   Clean up build files after installation
  -d, --debug   Enable debug mode for verbose logging
EOF
}

# Function to log messages
log() {
    local message="$1"
    local timestamp
    timestamp=$(date +'%m.%d.%Y %I:%M:%S %p')
    echo -e "${BLUE}[$timestamp]${NC} $message" | tee -a "$log_file"
}

# Function to log warning messages
warn() {
    local message="$1"
    local timestamp
    timestamp=$(date +'%m.%d.%Y %I:%M:%S %p')
    echo -e "${YELLOW}[$timestamp] WARNING:${NC} $message" | tee -a "$log_file"
}

# Function to log error messages and exit
fail() {
    local message="$1"
    local timestamp
    timestamp=$(date +'%m.%d.%Y %I:%M:%S %p')
    echo -e "${RED}[$timestamp] ERROR:${NC} $message" | tee -a "$log_file"
    echo -e "${RED}To report a bug, create an issue at:${NC} https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

# Function to perform cleanup
cleanup() {
    log "Cleaning up build files..."
    rm -rf "$cwd"
    log "Cleanup completed."
}

# Function to check and install dependencies
check_dependencies() {
    log "Checking dependencies..."

    local pkgs=(autoconf autoconf-archive autogen automake binutils build-essential ccache clang
                cmake curl git libgnome-desktop-3-dev libexempi-dev libportal-dev libportal-gtk3-dev
                libportal-gtk4-dev libgnome-desktop-4-dev libhandy-1-dev libpeas-dev libpeasd-3-dev
                libtool libtool-bin m4 meson nasm ninja-build python3 yasm itstool)

    local missing_pkgs=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ "${#missing_pkgs[@]}" -gt 0 ]; then
        warn "The following dependencies are missing: ${missing_pkgs[*]}"
        log "Installing missing dependencies..."
        sudo apt-get update
        sudo apt-get install -y "${missing_pkgs[@]}"
        log "Dependencies installed successfully."
    else
        log "All dependencies are already installed."
    fi
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            echo "Script version: $script_ver"
            exit 0
            ;;
        -c|--clean)
            cleanup
            exit 0
            ;;
        -d|--debug)
            set -x
            ;;
        *)
            warn "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# Check if script is run with root/sudo
if [ "$EUID" -eq 0 ]; then
    fail "You must run this script WITHOUT root/sudo."
fi

# Create output directory
log "Creating output directory..."
mkdir -p "$cwd"

# Set compiler optimization flags
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="$CFLAGS"
export CC CXX CFLAGS CXXFLAGS

# Set the PATH variable
PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH PATH

# Set the LIBRARY_PATH_PKG variable
export LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:$LIBRARY_PATH"

# Check and install dependencies
check_dependencies

# Download the archive file
log "Downloading archive file..."
archive_name=$(basename "$archive_url")
curl -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36" -Lso "$cwd/$archive_name" "$archive_url"

# Extract archive files
log "Extracting archive files..."
mkdir -p "$cwd/$archive_dir/build"
tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1 || fail "Failed to extract: $cwd/$archive_name"

# Build program from source
log "Building program from source..."
cd "$cwd/$archive_dir" || fail "Failed to change directory to $cwd/$archive_dir"
meson setup build --prefix="$install_dir" --buildtype=release --default-library=static --strip
ninja "-j$(nproc --all)" -C build || fail "Failed to execute: ninja -j$(nproc --all) -C build"
sudo ninja "-j$(nproc --all)" -C build install || fail "Failed to execute: sudo ninja -j$(nproc --all) -C build install"

# Create soft links
log "Creating soft links..."
for file in "$install_dir"/bin/*; do
    filename=$(basename "$file")
    linkname=$(echo "$filename" | sed 's/^.*-//')
    sudo ln -sf "$file" "/usr/local/bin/$linkname"
done

log "Build and installation completed successfully!"

# Prompt user to clean up files
read -rp "Do you want to clean up the build files? [y/N]: " choice
case "$choice" in
    y|Y)
        cleanup
        ;;
    *)
        log "Skipping cleanup."
        ;;
esac

log "Script execution completed."
