#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo 'This script must be run as root' 
   exit 1
fi

# SET VARIABLES (YOU MUST EDIT THESE)
# WARNING IT IS CONSIDERED BAD PRACTICE TO STORE PASSWORDS IN A FILE! MAKE SURE YOU CHANGE THESE AFTER YOU LOG INTO ARCH LINUX!
user_name='username'
user_password='password'
root_password='password'
computer_name='name'

# UPDATE THE SYSTEM CLOCK
timedatectl set-ntp true

clear

fdisk -l

printf "\n%s\n\n%s\n%s\n\n"                                   \
    'Warning! Continuing will format the drive you specify!'  \
    'Enter the full path of the drive you want to utilize...' \
    'Examples [ /dev/sda | /dev/nvme1n ]'
read -p 'Enter a drive path: ' drive_path

# Partition the disk (Warning: This will erase your disk!)
fdisk "$drive_path" <<EOF
g
n

+512M
t
1
n

+2G
t

82
n

w
EOF

# Format the partitions
regex_str='^\/dev\/sd'
if [[ ! $drive_path =~ $regex_str ]]; then
    mount "${drive_path}p2" /mnt
    mount --mkdir "${drive_path}p1" /mnt/efi
    swapon "${drive_path}p3"
else
    mount "${drive_path}2" /mnt
    mount --mkdir "${drive_path}1" /mnt/efi
    swapon "${drive_path}3"
fi
 
# Install the base system
pacstrap -K /mnt base linux linux-firmware linux-headers

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
# Set timezone
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime
hwclock --systohc

# Set localization
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
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
pacman -Sy --needed --noconfirm base-devel efibootmgr grub nano gnome-terminal gnome-text-editor gedit gedit-plugins nvidia networkmanager

# Enable the Network Manager service
systemctl enable NetworkManager

# Set up GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

mkdir /boot/efi/EFI/BOOT
cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

echo 'bcf boot add 1 fs0:\EFI\GRUB\grubx64.efi "Arch Linux Bootloader"' > /boot/efi/startup.sh
echo 'exit' >> /boot/efi/startup.sh
EOF

# Unmount partitions
umount -R /mnt
swapoff -a

# Reboot
printf "\n%s\n\n" 'Arch Linux is installed. Please reboot.'
