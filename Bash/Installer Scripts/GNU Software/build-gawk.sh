#!/usr/bin/env bash

# Purpose: Build GNU gawk optimized for x86_64/amd64 PCs
# Updated: 02.24.24
# Script version: 2.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Variables
script_ver="2.0"
cwd="$PWD/gawk-build-script"
install_dir="/usr/local/gawk"
gnu_ftp="https://ftp.gnu.org/gnu/gawk/"

# Functions
print_color() {
    case $1 in
        green) echo -e "${GREEN}$2${NC}" ;;
        red) echo -e "${RED}$2${NC}" ;;
        *) echo "$2" ;;
    esac
}

print_banner() {
    print_color green "gawk build script - v$script_ver"
    echo "==============================================="
}

cleanup() {
    print_color green "Cleaning up..."
    rm -fr "$cwd"
}

handle_failure() {
    print_color red "\nAn error occurred. Exiting..."
    cleanup
    exit 1
}

install_missing_packages() {
    print_color green "Checking and installing missing packages..."

    declare -A pkg_managers
    pkg_managers["/etc/redhat-release"]=yum
    pkg_managers["/etc/arch-release"]=pacman
    pkg_managers["/etc/gentoo-release"]=emerge
    pkg_managers["/etc/SuSE-release"]=zypper
    pkg_managers["/etc/debian_version"]=apt-get

    for file in "${!pkg_managers[@]}"; do
        if [[ -f $file ]]; then
            pkg_manager=${pkg_managers[$file]}
            break
        fi
    done

    case $pkg_manager in
        apt-get)
            pkgs=(autoconf autoconf-archive autogen automake binutils build-essential ccache
                  cmake curl git libtool libtool-bin lzip m4 nasm ninja-build texinfo zlib1g-dev
                  yasm)
            sudo apt update
            for pkg in "${pkgs[@]}"; do
                if ! dpkg -l | grep -qw $pkg; then
                    sudo apt -y install $pkg
                fi
            done
            ;;
        yum)
            pkgs=(autoconf automake binutils gcc gcc-c++ make)
            sudo yum install -y "${pkgs[@]}"
            ;;
        *)
            print_color red "Unsupported package manager. Please install dependencies manually."
            exit 1
            ;;
    esac
}

find_latest_release() {
    clear
    print_color green "Finding the latest gawk release..."
    latest_release=$(curl -sL $gnu_ftp | grep tar.lz | grep -v '.sig' | sed -n 's/.*href="\([^"]*\).*/\1/p' | sort -rV | head -n1)
    if [[ -z $latest_release ]]; then
        print_color red "Failed to find the latest gawk release. Exiting..."
        exit 1
    fi
    archive_url="${gnu_ftp}${latest_release}"
    archive_name="${latest_release}"
    archive_dir="${latest_release%.tar.lz}"
}

download_and_extract() {
    print_color green "Downloading and extracting gawk..."
    mkdir -p "$cwd"
    cd "$cwd" || exit
    if [[ ! -f $archive_name ]]; then
        curl -Lso $archive_name $archive_url
    fi
    mkdir -p "$archive_dir/build"
    tar --lzip -xf $archive_name -C "$archive_dir/build" --strip-components 1 || handle_failure
}

build_and_install() {
    print_color green "Building and installing gawk..."
    cd "$archive_dir/build" || exit 1
    ./configure --prefix="$install_dir" CFLAGS="-g -O3 -pipe -march=native" --build=x86_64-linux-gnu --host=x86_64-linux-gnu || handle_failure
    make "-j$(nproc)" || handle_failure
    sudo make install || handle_failure

    # Create symlinks
    sudo ln -sf "$install_dir/bin/gawk" "/usr/local/bin/gawk"
    sudo ln -sf "$install_dir/bin/gawk-${archive_dir#*-}" "/usr/local/bin/gawk-${archive_dir#*-}"

    print_color green "gawk installation completed successfully."
}

# Start the script
if [[ $EUID -eq 0 ]]; then
    print_color red "This script must be run with root or with sudo."
    exit 1
fi

print_banner
install_missing_packages
find_latest_release
download_and_extract
build_and_install
cleanup
