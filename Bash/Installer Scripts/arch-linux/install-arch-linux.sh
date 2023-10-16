#!/usr/bin/env bash

clear

################
## LIST DISKS ##
################

fdisk -l

####################
## PARTITION DISK ##
####################

# LOAD THE INTERACTIVE PARTITIONER PROGRAM
cfdisk /dev/nvmeXXX

# SET EFI PARTITION
/dev/nvmeXXp1
Size: +512M
Type: EFI
# SET EFI PARTITION
/dev/nvmeXXp2
Size: +364G
Type: Linux Filesystem
# SET EFI PARTITION
/dev/nvmeXXp3
Size: +80G
Type: Linux Filesystem
# SET EFI PARTITION
/dev/nvmeXXp4
Size: +32G
Type: Swap

#######################
## FORMAT PARTITIONS ##
#######################

# FORMAT PARTITION 1
mkfs.fat -F32 /dev/nvmeXXp1
# FORMAT PARTITION 2
mkfs.ext4 /dev/nvmeXXp2
# FORMAT PARTITION 3
mkfs.ext4 /dev/nvmeXXp3
# FORMAT PARTITION 4
mkswap /dev/nvmeXXp4
swapon /dev/nvmeXXp4

########################################
## GET THE UUID OF THE SWAP PARTITION ##
########################################

# ONLY IF NEEDED TRY THIS COMMAND
ls -lha /dev/disk/by-uuid

pacman -S core
pacman -S nano

# INPUT THE ABOVE UUID YOU FOUND IN THE FILE /ETC/FSTAB
nano /etc/fstab
ENTER NEW LINE = UUID=xxxxxx-xx-x-x-x-x-x none swap defaults 0 0

#################
## MOUNT DISKS ##
#################

# MOUNT PARTITION 2
mount /dev/nvmeXXp2 /mnt
# MOUNT PARTITION 3
mkdir /mnt/home
mount /dev/nvmeXXp3 /mnt/home
# VERIFY MOUNTS
lsblk

###############################
## INSTALL SOFTWARE ON MOUNT ##
###############################

pacstrap -i /mnt base base-devel efibootmgr grub linux linux-headers nano networkmanager

genfstab -U -p /mnt  >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash

nano /etc/locale.gen
FIND AND UNCOMMENT = #en_US.UTF-8 UTF-8

locale-gen
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime

hwclock --systohc --utc

nano "NAME-OF-COMPUTER" > /etc/hostname

nano /etc/hosts
NEW LINE = 127.0.1.1 localhost.localdomain NAME-OF-COMPUTER
systemctl enable NetworkManager

passwd root

mkdir /boot/efi

mount /dev/nvmeXXp1 /boot/efi
lsblk

grub-install --target=x86_x64-efi --bootloader-id=GRUB --efi-directory=/boot/efi

grub-mkconfig -o  /boot/grub/grub.cfg

mkdir /boot/efi/EFI/BOOT
cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

nano /boot/efi/startup.sh
LINE 1 = bcf boot add 1 fs0:\EFI\GRUB\grubx64.efi "My GRUB Bootloader"
LINE 2 = exit

# NEXT YOU NEED TO EXIT THE CURRENT LOGIN SHELL YOU ARE IN
exit
umount -R /mnt

# REBOOT THE PC
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
pacman -S pulseaudio pulseaudio-alsa xorg xorg-init xorg-server gnome lightdm lightdm-gtk-greeter nvidia virtualbox-guest-utils

# LOGIN TO GNOME DESKTOP
sudo systemctl start gdm.service
sudo systemctl enable gdm.service
sudo reboot

sudo pacman -S firefox vlc leafpad
