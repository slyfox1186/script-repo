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

##  GitHub Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/installer-scripts/gnu-software/build-eog
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
log_file=/dev/null

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
    rm -rf -- "$cwd"
}

# Function to check and install dependencies
check_dependencies() {
    log "Checking dependencies..."

    local pkgs=(autoconf autoconf-archive autogen automake binutils build-essential ccache clang
                cmake curl git libgnome-desktop-3-dev libexempi-dev libportal-dev libportal-gtk3-dev
                libportal-gtk4-dev libgnome-desktop-4-dev libhandy-1-dev libpeas-dev libtool libtool-bin m4 meson nasm ninja-build python3 yasm itstool)

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
            cleanup_files=true
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
cwd=$(gnu_new_workdir)
log_file="$cwd/build.log"
log "Creating output directory..."

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
gnu_curl -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36" -Lso "$cwd/$archive_name" "$archive_url"

# Extract archive files
log "Extracting archive files..."
mkdir -p "$cwd/$archive_dir/build"
tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1 || fail "Failed to extract: $cwd/$archive_name"

# Build program from source
log "Building program from source..."
cd "$cwd/$archive_dir" || fail "Failed to change directory to $cwd/$archive_dir"
meson setup build --prefix="$install_dir" --buildtype=release --default-library=static --strip
ninja "-j$gnu_jobs" -C build || fail "Failed to execute: ninja -j$gnu_jobs -C build"
sudo ninja "-j$gnu_jobs" -C build install || fail "Failed to execute: sudo ninja -j$gnu_jobs -C build install"

# Create soft links
log "Creating soft links..."
for file in "$install_dir"/bin/*; do
    [[ -e "$file" || -L "$file" ]] || continue
    filename=$(basename "$file")
    linkname=$filename
    sudo ln -sf "$file" "/usr/local/bin/$linkname"
done

log "Build and installation completed successfully!"

# Prompt user to clean up files
if [[ ${cleanup_files:-false} == true ]]; then
    choice=y
else
    read -rp "Do you want to clean up the build files? [y/N]: " choice || choice=n
fi
case "$choice" in
    y|Y)
        cleanup
        log_file=/dev/null
        ;;
    *)
        log "Skipping cleanup."
        ;;
esac

log "Script execution completed."
