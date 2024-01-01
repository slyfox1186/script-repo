#!/usr/bin/env bash

clear

set -e

localectl set-keymap --no-convert us

timedatectl set-ntp true

#######################
## FORMAT PARTITIONS ##
#######################

# FORMAT PARTITION 1
mkfs.fat -F32 /dev/nvmeXn1p1
# FORMAT PARTITION 2
mkswap /dev/nvmeXn1p2
# FORMAT PARTITION 3
mkfs.ext4 /dev/nvmeXn1p3

#################
## MOUNT DISKS ##
#################

# MOUNT PARTITION 3
mount /dev/nvmeXn1p3 /mnt
# MOUNT PARTITION 1
mount --mkdir /dev/nvmeXn1p1 /mnt/boot
# MOUNT PARTITION 2
swapon /dev/nvmeXn1p2

###############################
## INSTALL SOFTWARE ON MOUNT ##
###############################

pacstrap -K /mnt base efibootmgr grub linux linux-headers linux-firmware networkmanager

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash

ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime

hwclock --systohc

echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen

locale-gen

echo 'NAME-OF-COMPUTER' > /etc/hostname

mkinitcpio -P

echo '127.0.1.1 localhost.localdomain NAME-OF-COMPUTER' >> /etc/hosts

systemctl enable NetworkManager

passwd root

mkdir /boot/efi

mount /dev/nvmeXXp1 /boot/efi
lsblk

grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi

grub-mkconfig -o  /boot/grub/grub.cfg

mkdir /boot/efi/EFI/BOOT
cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

nano /boot/efi/startup.sh
LINE 1 = bcf boot add 1 fs0:\EFI\GRUB\grubx64.efi "My GRUB Bootloader"
LINE 2 = exit

# NEXT YOU NEED TO EXIT THE CURRENT LOGIN SHELL YOU ARE IN
exit

umount -R /mnt
reboot

####################################
## AFTER YOU LOAD INTO ARCH LINUX ##
####################################

# LOGIN TO ROOT AND ENTER THE ROOT PASSWD YOU SET
root
<ENTER THE ROOT PASSWORD>

# CREATE A NEW USER ACCOUNT
useradd -m -g users -G wheel -s /bin/bash user-name

# CREATE A NEW USER PASSWORD
passwd user-name
<ENTER THE USER PASSWORD>

# SET VISUDO ENV VAR
EDITOR=nano visudo

# NOW UNCOMMENT THE LINE
# %wheel ALL=(ALL:ALL) NOPASSWD: ALL

# ENTER THE NEWLY CREATED USER NAME TO LOGIN AS USER
user-name
<ENTER THE USER PASSWORD>

# INSTALL REQUIRED SOFTWARE USING PACMAN
pacman -Sy pulseaudio pulseaudio-alsa xorg xorg-xinit xorg-server gnome lightdm lightdm-gtk-greeter     nano gnome-terminal gnome-text-editor gedit gedit-plugins nvidia
# LOGIN TO GNOME DESKTOP
sudo systemctl enable gdm.service
sudo systemctl start gdm.service
sudo reboot