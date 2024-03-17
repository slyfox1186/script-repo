#!/usr/bin/env bash
# shellcheck disable=SC2162,SC2317

##  GitHub Script: https://github.com/slyfox1186/wsl2-kernel-build-script/blob/main/build-kernel
##  Purpose: Build Official WSL2 Kernels
##  Updated: 03.17.2024
##  Script version: 3.0

show_help() {
    echo "Usage: $(basename "$0") [options]"
    echo "Options:"
    echo "  -h, --help                            Show this help message."
    echo "  -v, --version VERSION                 Set a custom version number of the WSL2 kernel to install."
    echo "  -o, --output-directory <DIRECTORY>    Specify where the vmlinux file should be placed after build."
}

output_directory=""
kernel_version=""
version_type=""
version_specified="false"

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            version_specified="true"
            kernel_version="linux-msft-wsl-$2"
            shift 2
            ;;
        -o|--output-directory)
            output_directory="$2"
            shift 2
            ;;
        *)  shift
            ;;
    esac
done

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

# Prompting the user for input if no version specified
if ! $version_specified; then
    while true; do
        echo "Choose the WSL2 kernel version to download and install:"
        echo
        echo "1. Linux series 6 kernel"
        echo "2. Linux series 5 kernel"
        echo "3. Specific version"
        echo "4. Exit"
        echo
        read -p "Enter your choice (1-4): " choice

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
                read -p "Enter the version numbers (e.g., 5.15.90.1): " choice
                kernel_version="linux-msft-wsl-$choice"
                version_specified=true
                break
                ;;
            4)
                echo "Exiting the script."
                exit 0
                ;;
            *)  echo "Invalid choice. Please try again." ;;
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

parent="/tmp/wsl2-build-script" # parent parent directory
working="$parent/working"
error_log="$parent/error.log"

# Create the parent parent directory and the build directory within it
mkdir -p "$parent"
cd "$parent" || exit 1

# Set compiler optimizations
CC="gcc"
CXX="g++"
CFLAGS="-g -O3 -pipe -march=native"
CXXFLAGS="-g -O3 -pipe -march=native"
export CC CXX CFLAGS CXXFLAGS

announce_options() {
    # Announce options after all inputs have been processed
    echo "Final script configuration:"
    echo "Specific version specified: $version_specified"
    if $version_specified; then
        echo "Specific version: $kernel_version"
    else
        echo "Version: Using the latest available version"
    fi
    echo "Output directory: ${output_directory:-"Default directory ($PWD)"}"
}

install_required_packages() {
    local missing_packages=""
    local pkgs=(
        bc bison build-essential cmake curl debootstrap dwarves flex g++
        g++-s390x-linux-gnu gcc gcc-s390x-linux-gnu gdb-multiarch git libcap-dev
        libelf-dev libncurses-dev libncurses5 libncursesw5 libncursesw5-dev
        libssl-dev make pkg-config python3 qemu-system-misc qemu-utils rsync wget
    )

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -qo "ok installed"; then
            missing_packages+="$pkg "
        fi
    done

    if [[ -n "$missing_packages" ]]; then
        echo -e "\\nInstalling missing packages: $missing_packages\\n"
        sudo apt-get install -y $missing_packages
    else
        echo -e "\\nAll APT packages are already installed.\\n"
    fi
}

download_file() {
    local url="$1"
    local output_file="$2"

    if [[ -s "$output_file" ]]; then
        echo "File $output_file already exists and is not empty. Skipping download."
        return 0
    fi

    if ! command -v wget &>/dev/null; then
        echo "wget is not installed. Please install wget."
        exit 1
    fi
    echo -e "Downloading with wget...\\n"
    wget --show-progress -cqO "$output_file" "$url"
}

source_the_latest_release_version() {
    local version_type="$1"
    local url="https://github.com/microsoft/WSL2-Linux-Kernel/tags/"
    local pattern="linux-msft-wsl-$version_type\\.[0-9]+\\.[0-9]+\\.[0-9]+"

    curl -fsS "$url" | grep -oP "$pattern" | head -n1
}

build_kernel_without_progress() {
    echo "Installing the WSL2 Kernel"
    echo "========================================="
    if ! echo "yes" | make "-j$(nproc --all)" KCONFIG_CONFIG="Microsoft/config-wsl" 2>>"$error_log"; then
        echo -e "\\nBuild process terminated with errors. Please check the error log below:\\n"
        cat "$error_log"
        return 1
    fi
    if ! make modules_install headers_install; then
        echo "Failed to make modules and install headers"
        exit 1
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

    echo "Downloading kernel version $version..."

    if [[ -z "$version" ]]; then
        echo "Failed to find the latest version. Exiting."
        echo
        exit 1
    fi

    download_file "https://github.com/microsoft/WSL2-Linux-Kernel/archive/refs/tags/$version.tar.gz" "$parent/$version.tar.gz"

    echo -e "Successfully downloaded the source code file \"$version\"\\n"

    # Remove any leftover files from previous runs
    [[ -d "$working" ]] && rm -fr "$working"

    # Ge the working directory ready
    mkdir -p "$working"

    if ! tar -zxf "$parent/$version.tar.gz" -C "$working" --strip-components 1; then
        echo "Failed to extract the archive. Deleting the corrupt archive."
        rm -f "$parent/$version.tar.gz"
        echo
        echo "The archive file has been deleted due to extraction failure."
        echo "Please run the script again to fix the issue."
        exit 1
    fi

    cd "$working" || exit 1
    echo -e "\\nBuilding the kernel...\\n"
    if ! build_kernel_without_progress; then
        rm -fr "$working"
        echo "Error log:"
        cat "$error_log"
        echo -e "\\nKernel build failed. Please check the error log above for more information.\\n"
        return 1
    else
        locate_vmlinux=$(find $PWD -type f -name vmlinux | head -n1)
        if [[ -f "$locate_vmlinux" ]]; then
            cp -f "$locate_vmlinux" "$script_dir/vmlinux"
            echo -e "\\nKernel build successful. vmlinux moved to the specified output directory: $script_dir\\n"

            local choic
            read -p "Do you want to delete the build directory? (y/n): " choice
            if [[ "$choice" = "y" ]]; then
                rm -fr "$working"
                echo -e "\\nBuild directory cleaned up.\\n"
            else
                echo -e "\\nBuild directory retained as per user choice.\\n"
            fi
        else
            echo "Error: vmlinux file not found. Please check the build process."
            return 1
        fi
    fi
}

install_kernel