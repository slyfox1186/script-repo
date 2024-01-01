#!/bin/bash

# Set the disk variable (modify as needed)
DISK="/dev/nvme1n"

# Wipe the disk
sgdisk --zap-all $DISK

# Create partitions
# EFI partition
sgdisk -n 1:0:+550M -t 1:EF00 $DISK
# Swap partition
sgdisk -n 2:0:+2G -t 2:8200 $DISK
# Root partition
sgdisk -n 3:0:0 -t 3:8300 $DISK

# Inform the OS of partition table changes
partprobe $DISK

# Format partitions
mkfs.fat -F32 "${DISK}1"     # EFI partition
mkswap "${DISK}2"            # Swap partition
swapon "${DISK}2"
mkfs.ext4 "${DISK}3"         # Root partition

# Mount the partitions
mount "${DISK}3" /mnt
mkdir /mnt/boot
mount "${DISK}1" /mnt/boot

# Install base system and basic packages (including grub for UEFI)
pacstrap /mnt base linux linux-firmware vim intel-ucode grub efibootmgr networkmanager

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the system
arch-chroot /mnt

# Timezone and locale settings (modify as needed)
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname configuration (modify as needed)
echo "myarch" > /etc/hostname
echo -e "127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.1.1\tmyarch.localdomain\tmyarch" >> /etc/hosts

# Set root password (change as needed)
echo root:password | chpasswd

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
systemctl enable NetworkManager

# Exit chroot
exit

# Unmount all partitions
umount -R /mnt

echo "Arch Linux is installed. Please reboot."
