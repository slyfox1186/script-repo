#!/usr/bin/env bash
# shellcheck disable=SC2162,SC2317

# GitHub: https://github.com/slyfox1186/wsl2-kernel-build-script/blob/main/build-kernel.sh
# Purpose: Build Official WSL2 Kernels
# Updated: 07.03.24
# Script version: 3.3

# Color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

show_help() {
    script_name="${0##*/}"
    echo "Usage: $script_name [options]"
    echo "Options:"
    echo "  -h, --help                            Show this help message."
    echo "  -v, --version VERSION                 Set a custom version number of the WSL2 kernel to install."
    echo "  -o, --output-directory <DIRECTORY>    Specify where the vmlinux file should be placed after build."
}

log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

output_directory=""
kernel_version=""
version_type=""
version_specified="false"

# Parse command line options
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            version_specified="true"
            kernel_version="$2"
            shift 2
            ;;
        -o|--output-directory)
            output_directory="$2"
            shift 2
            ;;
        *)
            fail "Invalid option: $1"
            ;;
    esac
done

# Check if the script is run with root privileges
if [[ "$EUID" -ne 0 ]]; then
    fail "You must run this script with root or sudo."
fi

list_available_versions() {
    local version

    echo
    log "Available kernel versions:"
    echo
    version=$(curl -fsS "https://github.com/microsoft/WSL2-Linux-Kernel/tags/" | grep -oP 'linux-msft-wsl-\K\d+([\d.])+(?=\.tar\.[a-z]+)' | sort -ruV)

    if [[ -n "$version" ]]; then
        echo "$version"
    else
        echo "No version found."
    fi
}

# Prompting the user for input if no version specified
if ! $version_specified; then
    while true; do
        echo
        echo "Choose the WSL2 kernel version to download and install:"
        echo
        echo "1. Linux series 6 kernel"
        echo "2. Linux series 5 kernel"
        echo "3. Specific version"
        echo "4. List available versions"
        echo "5. Exit"
        echo
        read -rp "Enter your choice (1-5): " choice

        case "$choice" in
            1)
                version_type="6"
                break
                ;;
            2)
                version_type="5"
                break
                ;;
            3)
                read -rp "Enter the version numbers (e.g., 5.15.90.1): " choice
                kernel_version="$choice"
                version_specified=true
                break
                ;;
            4)
                list_available_versions
                ;;
            5)
                echo "Exiting the script."
                exit 0
                ;;
            *)
                fail "Invalid choice. Please try again."
                ;;
        esac
    done
fi

# Ensure the directory for 'vmlinux' is prepared.
if [[ -z "$output_directory" ]]; then
    script_dir="$PWD" # Use current directory if no output directory is specified
else
    script_dir="$output_directory"
    mkdir -p "$script_dir" # Create output directory if it does not exist
fi

# Set compiler optimizations
CC="gcc"
CXX="g++"
CFLAGS="-O2 -pipe -march=native" # Aggressive optimization flags
CXXFLAGS="$CFLAGS" # Aggressive optimization flags
LDFLAGS="-L/usr/lib/x86_64-linux-gnu"
CPPFLAGS="-I/usr/local/include -I/usr/include"
PATH="/usr/lib/ccache:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig"
export CC CXX CFLAGS CXXFLAGS LDFLAGS CPPFLAGS PATH PKG_CONFIG_PATH

announce_options() {
    # Announce options after all inputs have been processed
    echo
    echo "Final script configuration:"
    echo "==================================="
    log "Specific version specified: $version_specified"
    if $version_specified; then
        log "Specific version: $kernel_version"
    else
        log "Version: Using the latest available version"
    fi
    log "Output directory: ${output_directory:-"Default directory ($PWD)"}"
}

prompt_wsl_script() {
    log "Do you want to run the automatic file generator for .wslconfig?"
    read -rp "Please enter your choice (y/n): " choice
    echo

    case "$choice" in
        [yY]*)
            bash <(curl -fsSL "https://raw.githubusercontent.com/slyfox1186/wsl2-kernel-build-script/main/wslconfig-generator.sh")
            ;;
        [nN]*)
            exit 0
            ;;
        *)
           warn "Bad user input..."
           unset choice
           prompt_wsl_script
           ;;
    esac
}

install_required_packages() {
    local -a pkgs missing_packages=()
    local pkg
    pkgs=(
        bc bison build-essential ccache cmake curl debootstrap dwarves flex g++
        g++-s390x-linux-gnu gcc gcc-s390x-linux-gnu gdb-multiarch git libcap-dev
        libelf-dev libssl-dev make pahole pkg-config python3 qemu-system-misc
        qemu-utils rsync wget
    )

    # Determine additional packages based on the OS version
    os_version=$(grep -oP '(?<=^VERSION_ID=")[^"]+' /etc/os-release)
    case "$os_version" in
        "24.04")
            pkgs+=(libelf1t64 libncursesw6 libncurses-dev)
            ;;
        *)
            pkgs+=(libncurses-dev libncurses5 libncursesw5 libncursesw5-dev)
            ;;
    esac

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -qo "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log "Installing missing packages: ${missing_packages[*]}"
        for pkg in "${missing_packages[@]}"; do
            if apt install -y "$pkg"; then
                log "Successfully installed package: $pkg"
            else
                warn "Failed to install package: $pkg"
            fi
        done
    else
        log "All APT packages are already installed."
    fi
}

download_file() {
    local output_file url
    url="$1"
    output_file="$2"

    if [[ -s "$output_file" ]]; then
        log "File $output_file already exists and is not empty. Skipping download."
        return 0
    fi

    if ! command -v wget &>/dev/null; then
        echo "wget is not installed. Please install wget."
        exit 1
    fi
    log "Downloading with wget..."
    wget --show-progress -cqO "$output_file" "$url"
}

source_the_latest_release_version() {
    local version_type
    version_type="$1"

    curl -fsS "https://github.com/microsoft/WSL2-Linux-Kernel/tags/" | grep -oP "linux-msft-wsl-\K${version_type}\.([\d.])+(?=\.tar\.[a-z]+)" | head -n1
}

build_kernel_without_progress() {
    echo
    echo "Installing the WSL2 Kernel"
    echo "========================================="
    echo
    if ! echo "yes" | make "-j$(nproc --all)" KCONFIG_CONFIG="Microsoft/config-wsl" 2>>"$error_log"; then
        log "Build process terminated with errors. Please check the error log below:"
        cat "$error_log"
        return 1
    fi
    if ! make modules_install headers_install; then
        fail "Failed to make modules and install headers"
    fi
    return 0
}

install_kernel() {
    clear
    announce_options
    install_required_packages

    if [[ -n "$kernel_version" ]]; then
        version="$kernel_version"
    else
        version=$(source_the_latest_release_version "$version_type")
    fi

    log "Downloading kernel version $version..."

    if [[ -z "$version" ]]; then
        fail "Failed to find the latest version. Exiting."
    fi

    download_file "https://github.com/microsoft/WSL2-Linux-Kernel/archive/refs/tags/linux-msft-wsl-$version.tar.gz" "$parent/$version.tar.gz"

    log "Successfully downloaded the source code file \"$version\""

    # Remove any leftover files from previous runs
    [[ -d "$working" ]] && rm -fr "$working"

    # Get the working directory ready
    mkdir -p "$working"

    if ! tar -zxf "$parent/$version.tar.gz" -C "$working" --strip-components 1; then
        warn "Failed to extract the archive. Deleting the corrupt archive."
        rm -f "$parent/$version.tar.gz"
        log "The archive file has been deleted due to extraction failure. Please re-run the script."
        exit 1
    fi

    cd "$working" || exit 1
    log "Building the kernel..."
    if ! build_kernel_without_progress; then
        rm -fr "$working"
        log "Error log:"
        cat "$error_log"
        fail "Kernel build failed. Please check the error log above for more information."
    else
        locate_vmlinux=$(find "$PWD" -maxdepth 1 -type f -name vmlinux | head -n1)
        if [[ -f "$locate_vmlinux" ]]; then
            cp -f "$locate_vmlinux" "$script_dir/vmlinux"
            log "Kernel build successful. vmlinux moved to the specified output directory: $script_dir"

            local choice
            read -rp "Do you want to delete the build directory? (y/n): " choice
            if [[ "$choice" = "y" ]]; then
                rm -fr "$working"
                log "Build directory cleaned up."
            else
                log "Build directory retained as per user choice."
            fi
        else
            fail "Error: vmlinux file not found. Please check the build process."
        fi
    fi
}

# Run the kernel building code
cwd="$PWD"
parent="/tmp/wsl2-build-script"
working="$parent/working"
error_log="$parent/error.log"

# Create the parent parent directory and the build directory within it
mkdir -p "$parent"
cd "$parent" || exit 1

install_kernel
if [[ -f "$cwd/vmlinux" ]]; then
    log "The file \"vmlinux\" can be found in this script's directory."
else
    warn "Failed to move the file \"vmlinux\" to the script's directory."
fi

# Prompt and run the .wslconfig generator script
cd "$cwd" || exit 1
prompt_wsl_script
if [[ -f ".wslconfig" ]]; then
    log "The \".wslconfig\" file can be found in this script's directory."
else
    warn "The \".wslconfig\" file failed to generate."
fi