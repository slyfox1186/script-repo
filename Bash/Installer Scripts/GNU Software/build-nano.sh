#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/edit/main/Bash/Installer%20Scripts/GNU%20Software/build-nano
##  Purpose: build gnu nano
##  Updated: 05.01.24
##  Script version: 2.2

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
script_ver="2.2"
archive_url="https://ftp.gnu.org/gnu/nano/"
cwd="$PWD/nano-build-script"
install_dir="/usr/local/nano-latest"
verbose=true
keep_build_files=false
compiler="gcc"
prefix="$install_dir"
jobs="$(nproc --all)"

# Functions
log() {
    if [ "$verbose" = true ]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "${RED}To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues${NC}\\n"
    exit 1
}

cleanup() {
    if [ "$keep_build_files" = false ]; then
        sudo rm -rf "$cwd"
        echo
        log "Build directory removed."
    fi
}

install_dependencies() {
    local pkgs=(autoconf autoconf-archive autogen automake build-essential curl libc6-dev libintl-perl libncurses5-dev
                libpth-dev libticonv-dev libtool libtool-bin lzip lzma-dev nasm texinfo)
    local missing_pkgs=()

    echo
    log "Installing dependencies..."
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        sudo apt update
        sudo apt install -y "${missing_pkgs[@]}"
        sudo apt -y autoremove
    fi
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Build GNU nano from source."
    echo
    echo "Options:"
    echo "  -h, --help           Show this help message and exit"
    echo "  -v, --version        Set the version number of nano to install"
    echo "  -l, --list           List all available versions of nano"
    echo "  -j, --jobs           Set the number of parallel jobs to use"
    echo "  -k, --keep           Keep the build files after the script has finished"
    echo "  -c, --compiler       Set the compiler (default: gcc)"
    echo "  -p, --prefix         Set the prefix configure uses"
    echo "  -n, --no-verbose     Turn off verbose mode and suppress logging"
}

# Check if running as root
if [[ "$EUID" -eq 0 ]]; then
    fail "You must run this script without root or with sudo."
fi

echo "As of 05.01.2024 the latest version of nano 8.0 fails to build on Ubuntu Jammy."
echo "If you encounter this issue know you are not alone."
echo "If that is so I recommend version 7.2 which you can install using this command: $0 -v 7.2"
echo
read -p "Press enter to continue."

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            version="$2"
            shift 2
            ;;
        -l|--list)
            list_versions=true
            shift
            ;;
        -j|--jobs)
            jobs="$2"
            shift 2
            ;;
        -k|--keep)
            keep_build_files=true
            shift
            ;;
        -c|--compiler)
            compiler="$2"
            shift 2
            ;;
        -p|--prefix)
            prefix="$2"
            shift 2
            ;;
        -n|--no-verbose)
            verbose=false
            shift
            ;;
        *)
            warn "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# List available versions if -l or --list is provided
if [ "$list_versions" = true ]; then
    echo
    log "Available nano versions:"
    curl -s "$archive_url" | grep -oP '(?<=nano-)[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -uV
    exit 0
fi

# Get latest version number if not provided with -v or --version
if [ -z "$version" ]; then
    version=$(curl -s "$archive_url" | grep -oP '(?<=nano-)[0-9]+\.[0-9]+' | sort -V | tail -1)
fi

archive_dir="nano-$version"
archive_name="nano-$version.tar.xz"
archive_url="$archive_url$archive_name"

echo
log "nano build script - v${script_ver}"
log "======================================="
echo

# Set compiler and flags
export CC="$compiler" CXX="$compiler++"
export CFLAGS="-g -O3 -march=native -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=2"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="-D_FORTIFY_SOURCE=2"
export LDFLAGS="-Wl,-z,relro,-z,now"

# Set PATH and PKG_CONFIG_PATH
PATH="/usr/local/bin:/usr/bin:/bin"
export PATH

PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/pkgconfig"
export PKG_CONFIG_PATH

# Install dependencies
install_dependencies

# Create working directory
echo
log "Creating working directory..."
mkdir -p "$cwd"

# Download archive
if [ ! -f "$cwd/$archive_name" ]; then
    log "Downloading $archive_url..."
    curl -Lso "$cwd/$archive_name" "$archive_url"
else
    log "Archive already exists: $cwd/$archive_name"
fi

# Extract archive
log "Extracting archive..."
mkdir -p "$cwd/$archive_dir/build"
tar -xf "$cwd/$archive_name" -C "$cwd/$archive_dir" --strip-components 1 || fail "Failed to extract archive"

# Build and install
cd "$cwd/$archive_dir" || fail "Failed to change directory to $cwd/$archive_dir"
autoreconf -fi
cd build || fail "Failed to change directory to build"

../configure --prefix="$prefix" \
             --disable-nls \
             --enable-threads=posix \
             --enable-utf8 \
             --enable-year2038

echo
log "Building and installing nano..."
make "-j$jobs" || fail "Failed to build nano"
sudo make install || fail "Failed to install nano"

# Create symlinks
echo
log "Creating symlinks..."
for file in "$prefix"/bin/*; do
    filename=$(basename "$file")
    linkname=${filename#*-}
    sudo ln -sf "$file" "/usr/local/bin/$linkname" || warn "Failed to create symlink for $filename"
done

# Cleanup files
cleanup

echo
log "nano build script completed successfully!"
log "Make sure to star this repository to show your support: https://github.com/slyfox1186/script-repo"\
