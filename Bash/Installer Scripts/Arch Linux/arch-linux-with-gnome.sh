#!/bin/bash

# Variables
DISK="/dev/nvmeX"  # Replace with your NVMe drive, e.g., /dev/nvme0n1
EFI_SIZE="512M"      # Size of the EFI partition
SWAP_SIZE="2G"       # Size of the swap partition

# Update the system clock
timedatectl set-ntp true

# Wipe the disk and create new GPT partition table
parted -s $DISK mklabel gpt

# Create partitions
# EFI partition
parted -s $DISK mkpart ESP fat32 1MiB $EFI_SIZE
parted -s $DISK set 1 esp on

# Swap partition
parted -s $DISK mkpart primary linux-swap $EFI_SIZE $(($EFI_SIZE+$SWAP_SIZE))

# Root partition
parted -s $DISK mkpart primary ext4 $(($EFI_SIZE+$SWAP_SIZE)) 100%

# Format the partitions
mkfs.fat -F32 ${DISK}n1p1
mkswap ${DISK}n1p2
mkfs.ext4 ${DISK}n1p3

# Enable swap partition
swapon ${DISK}n1p2

# Mount the file systems
mount ${DISK}p3 /mnt
mkdir -p /mnt/boot
mount ${DISK}p1 /mnt/boot
