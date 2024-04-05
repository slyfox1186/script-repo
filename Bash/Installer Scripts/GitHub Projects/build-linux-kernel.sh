#!/bin/bash

# Function to handle errors
handle_error() {
    echo "Error: $1"
    exit 1
}

# Function to display help menu
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Automates the process of downloading, configuring, building, and installing the Linux kernel."
    echo
    echo "Options:"
    echo "  -v, --version VERSION    Specify the kernel version to install (e.g., 5.15.0)"
    echo "  -c, --config CONFIG      Specify the kernel configuration file to use"
    echo "  -m, --menuconfig         Run 'make menuconfig' for manual kernel configuration"
    echo "  -h, --help               Display this help menu"
    echo
    echo "If no options are provided, the script will download and install the latest stable kernel version."
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -v|--version)
            KERNEL_VERSION="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -m|--menuconfig)
            MENUCONFIG=true
            shift
            ;;
        -h|--help)
            display_help
            exit 0
            ;;
        *)
            handle_error "Unknown parameter passed: $1"
            exit 1
            ;;
    esac
done

# Install required dependencies
sudo apt update
sudo apt install -y git build-essential libncurses-dev bison flex libssl-dev libelf-dev

# Create a temporary directory for the kernel source
temp_dir=$(mktemp -d)
cd "$temp_dir" || handle_error "Failed to change directory to $temp_dir"

# Get the latest stable kernel version if not specified
if [[ -z $KERNEL_VERSION ]]; then
    KERNEL_VERSION=$(curl -fsS https://www.kernel.org/ | grep -A1 'latest_link' | sort -uV | head -n1 | sed -e 's/>.*[^"]//g' | grep -oP '[0-9]\.[0-9]\.[0-9]')
fi

# Download the specified kernel source
wget --show-progress -cqO "linux-$KERNEL_VERSION.tar.xz" "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/linux-$KERNEL_VERSION.tar.xz"
mkdir "linux-$KERNEL_VERSION"
tar -xf "linux-$KERNEL_VERSION.tar.xz" -C "linux-$KERNEL_VERSION" --strip-components 1
cd "linux-$KERNEL_VERSION" || handle_error "Failed to change directory to linux-$KERNEL_VERSION"

# Configure the kernel
if [[ -n $CONFIG_FILE ]]; then
    cp "$CONFIG_FILE" .config
elif [[ $MENUCONFIG = true ]]; then
    make menuconfig
else
    make defconfig
fi

# Build the kernel
make "-j$(nproc --all)"

# Install the kernel modules
sudo make modules_install

# Install the kernel
sudo make install

# Update initramfs
update-initramfs -c -k "$KERNEL_VERSION"

# Update GRUB
sudo update-grub

# Cleanup
cd "$HOME" || handle_error "Failed to change directory to $HOME"
rm -rf "$temp_dir"

echo "Linux kernel $KERNEL_VERSION has been successfully installed and configured."
echo "Please reboot your system to start using the new kernel."
