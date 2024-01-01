#!/bin/bash

# Set the disk variable (modify as needed)
DISK='/dev/nvmeX'
user_name=""
user_password=""
root_password=""
computer_name=""

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
mkfs.fat -F32 "${DISK}n1p1"     # EFI partition
mkswap "${DISK}n1p2"            # Swap partition
swapon "${DISK}n1p2"
mkfs.ext4 "${DISK}n1p3"         # Root partition

# Mount the partitions
mount "${DISK}n1p3" /mnt
mount --mkdir "${DISK}n1p1" /mnt/boot

# Install base system and basic packages (including grub for UEFI)
pacstrap -K /mnt base base-devel efibootmgr grub linux linux-firmware linux-headers nano networkmanager vim

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the system
arch-chroot /mnt

# Timezone and locale settings (modify as needed)
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime
hwclock --systohc

# Set localization
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# Set hostname
echo "$computer_name" > /etc/hostname

mkinitcpio -P

# Set the hosts file
echo '127.0.0.1    localhost' > /etc/hosts
echo '::1          localhost' >> /etc/hosts
echo '' >> /etc/hosts
echo "127.0.1.1    localhost.localdomain $computer_name" >> /etc/hosts

# Set the root password (use a secure password here)
echo "root:$root_password" | chpasswd

# Create a new user with a password
useradd -m $user_name
echo "$user_name:$user_password" | chpasswd

# Install essential packages
pacman -Sy --needed --noconfirm clang efibootmgr gcc gnome-terminal gnome-text-editor gedit gedit-plugins nvidia

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

mkdir /boot/efi/EFI/BOOT
cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

echo 'bcf boot add 1 fs0:\EFI\GRUB\grubx64.efi "Arch Linux Bootloader"' > /boot/efi/startup.sh
echo 'exit' >> /boot/efi/startup.sh

# Enable NetworkManager
systemctl enable NetworkManager

# Exit chroot
exit

# Unmount all partitions
umount -R /mnt
swapoff -a

printf "\n%s\n\n" 'Arch Linux is installed. Please reboot.'

# Install essential packages
pacman -Sy --needed --noconfirm base-devel efibootmgr grub nano gnome-terminal gnome-text-editor gedit gedit-plugins nvidia networkmanager
