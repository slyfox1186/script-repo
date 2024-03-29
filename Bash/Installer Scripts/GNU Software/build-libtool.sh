#!/usr/bin/env bash

# Github script information
# Purpose: build gnu libtool from source.
# Updated: 03.02.24
# Script version: 1.3
# Github repository: https://github.com/slyfox1186/script-repo

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "\nThis script must be run with root privileges. Please run it again with 'sudo' or as root.\n"
    exit 1
fi

# Initialize script variables
script_ver="1.3"
archive_dir="libtool-2.4.7"
archive_url="https://ftp.gnu.org/gnu/libtool/$archive_dir.tar.xz"
cwd="$PWD/libtool-build-script"

# Display script banner
echo -e "\n========== libtool Build Script v$script_ver ==========\n"

# Create the build directory
echo "Preparing build environment..."
rm -fr "$cwd" && mkdir -p "$cwd"

# Set environment variables for building
export CC="gcc"
export CXX="g++"
export CFLAGS="-g -O3 -pipe -fno-plt -march=native"
export CXXFLAGS="$CFLAGS"

# Install required packages
echo "Installing required packages..."
apt update && apt install autoconf autoconf-archive autogen automake build-essential ccache cmake curl git libltdl-dev

# Download libtool archive
echo "Downloading libtool archive..."
if [ ! -f "$cwd/$archive_dir.tar.xz" ]; then
    curl -Lso "$cwd/$archive_dir.tar.xz" "$archive_url" || { echo "Failed to download libtool archive."; exit 1; }
fi

# Extract the archive
echo "Extracting archive..."
mkdir -p "$cwd/$archive_dir/build"
tar -xf "$cwd/$archive_dir.tar.xz" -C "$cwd/$archive_dir" --strip-components=1 || { echo "Failed to extract libtool archive."; exit 1; }

# Build libtool from source
echo "Building libtool from source..."
cd "$cwd/$archive_dir/build" || exit 1
../configure --prefix=/usr/local --enable-ltdl-install
if ! make "-j$(nproc)"; then
     echo "Failed to build and install libtool. Line: $LINENO"
     exit 1
fi
if ! make install; then
     echo "Failed to build and install libtool. Line: $LINENO"
     exit 1
fi

# Cleanup build files
echo
read -p "Do you want to clean up the build files? [Y/n]: " choice
if [[ "$choice" =~ ^(yes|y| ) ]] || [[ -z "$choice" ]]; then
    echo "Cleaning up..."
    rm -fr "$cwd"
fi

# Completion message
echo -e "\nlibtool has been successfully built and installed.\n"
echo "Thank you for using this script. For more tools and scripts, visit our GitHub repository:"
echo "https://github.com/slyfox1186/script-repo"
