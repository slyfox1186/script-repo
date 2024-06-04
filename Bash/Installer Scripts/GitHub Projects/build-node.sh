#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-node.sh
# Script version: 1.1
# Last update: 05-28-24

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or with sudo."
    exit 1
fi

# ANSI color codes
cyan='\033[0;36m'
green='\033[0;32m'
red='\033[0;31m'
reset='\033[0m'

cwd="$PWD/nodejs-build-script"

if [[ -d "$cwd" ]]; then
    read -p "An existing build directory was found. Do you want to delete it before continuing? (y/n): " delChoice
    case "$delChoice" in
        [yY]*) sudo rm -fr "$cwd" ;;
        [nN]*) ;;
        *) echo -e "${red}Invalid choice. Exiting.${reset}"; exit 1 ;;
    esac
fi

# Function to print colored text
print_color() {
    local color msg
    color="$1"
    msg="$2"
    case "$color" in
        cyan) echo -e "${cyan}${msg}${reset}" ;;
        green) echo -e "${green}${msg}${reset}" ;;
        red) echo -e "${red}${msg}${reset}" ;;
        *) echo -e "${msg}" ;;
    esac
}

# Function to handle errors
error() {
    print_color red "Error: $1"
    exit 1
}

# Set optimization flags based on the CPU architecture
arch=$(uname -m)
optflags="-O2"
if [[ "$arch" == "x86_64" ]]; then
    optflags="-O2 -pipe -march=native"
elif [[ "$arch" == "armv7l" || "$arch" == "aarch64" ]]; then
    optflags="-O2 -mcpu=native -mtune=native"
fi

PATH="/usr/lib/ccache:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
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

# Create the build directory and change into it
mkdir -p "$cwd"
cd "$cwd" || error "Failed to change directory to $cwd"

# Download Node.js source code
print_color cyan "Downloading Node.js source code..."
wget --show-progress -cqO "node-v$version.tar.gz" "https://nodejs.org/dist/v$version/node-v$version.tar.gz" || error "Failed to download Node.js source code"

# Extract the source code
print_color cyan "Extracting the source code..."
tar -zxf "node-v$version.tar.gz" || error "Failed to extract the source code"
cd "node-v$version" || error "Failed to change directory to node-v$version"

# Configure and build Node.js
print_color cyan "Configuring Node.js..."
options=("--ninja" "--prefix=/usr/local" "--openssl-use-def-ca-store" "--openssl-system-ca-path=/etc/ssl/certs/cacert.pem")
./configure "${options[@]}" || error "Failed to configure Node.js"

print_color green "Node.js configuration completed successfully"

print_color cyan "Building Node.js..."
ninja "-j$(nproc --all)" -C out/Release || error "Failed to build Node.js"

print_color green "Node.js build completed successfully"

# Install Node.js
print_color cyan "Installing Node.js..."
sudo make install || error "Failed to install Node.js"

print_color green "Node.js installation completed successfully"

# Clean up
print_color cyan "Cleaning up..."
sudo rm -fr "$cwd"

print_color green "Node.js $version has been successfully installed with optimizations!"
