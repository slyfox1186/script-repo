#!/usr/bin/env bash

# ANSI color codes
cyan='\033[0;36m'
green='\033[0;32m'
red='\033[0;31m'
reset='\033[0m'

cwd="$PWD/nodejs-build-script"

mkdir -p "$cwd"

cd "$cwd" || exit 1

# Function to print colored text
print_color() {
    case "$1" in
        cyan)
            color=$cyan
            ;;
        green)
            color=$green
            ;;
        red)
            color=$red
            ;;
        *)
            color=$reset
            ;;
    esac
    echo -e "${color}$2${reset}"
}

# Function to handle errors
error() {
    print_color red "Error: $1"
    exit 1
}

# Set optimization flags based on the CPU architecture
arch=$(uname -m)
if [[ "$arch" == "x86_64" ]]; then
    optflags="-O3 -pipe -march=native"
elif [[ "$arch" == "armv7l" || "$arch" == "aarch64" ]]; then
    optflags="-O3 -mcpu=native -mtune=native"
else
    optflags="-O2"
fi

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig"
export PATH PKG_CONFIG_PATH

# Set compiler flags
CC="gcc"
CXX="g++"
CFLAGS="$optflags"
CXXFLAGS="$optflags"
export CC CXX CFLAGS CXXFLAGS

# Get the latest LTS version of Node.js
print_color cyan "Fetching the latest LTS version of Node.js..."
version=$(curl -fsSL "https://nodejs.org/en/download/source-code/" | grep -oP 'node-v?\K\d+\.\d+\.\d+' || error "Failed to fetch the latest LTS version")
print_color green "Latest LTS version: $version"

# Download Node.js source code
print_color cyan "Downloading Node.js source code..."
wget --show-progress -cqO "node-v$version.tar.gz" "https://nodejs.org/dist/v$version/node-v$version.tar.gz" || error "Failed to download Node.js source code"

# Extract the source code
print_color cyan "Extracting the source code..."
tar -zxf "node-v$version.tar.gz" || error "Failed to extract the source code"
cd "node-v$version"

# Configure and build Node.js
print_color cyan "Configuring Node.js..."
options=("--ninja" "--node-builtin-modules-path=$PWD" "--enable-lto"  "--openssl-use-def-ca-store" "--openssl-system-ca-path=/etc/ssl/certs/cacert.pem" "--v8-enable-hugepage")
if ./configure "${options[@]}"; then
    print_color green "Node.js configuration completed successfully"
else
    error "Failed to configure Node.js"
fi

print_color cyan "Building Node.js..."
if ninja "-j$(nproc --all)" -C out/Release; then
    print_color green "Node.js build completed successfully"
else
    error "Failed to build Node.js"
fi

# Install Node.js
print_color cyan "Installing Node.js..."
if sudo ninja install -C out/Release; then
    print_color green "Node.js installation completed successfully"
else
    error "Failed to install Node.js"
fi

# Clean up
print_color cyan "Cleaning up..."
sudo rm -fr "$cwd"

print_color green "Node.js $version has been successfully installed with optimizations!"
