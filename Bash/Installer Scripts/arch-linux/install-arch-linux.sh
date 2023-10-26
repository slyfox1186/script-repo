#!/usr/bin/env bash

clear

loadkeys en_US.UTF-8
# OR TRY
loadkeys C.UTF-8

localectl set-keymap --no-convert en_US.UTF-8

setfont ter-132b

cat /sys/firmware/efi/fw_platform_size

timedatectl

################
## LIST DISKS ##
################

clear
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
## SET SWAP PARTITION ##
# ON UEFI SWAP PARTITIONS ARE TYPE = 0657FD6D-A4AB-43C4-84E5-0933C84B4F4F
/dev/nvmeXXp2
Size: +32G
Type: Linux swap
# SET ROOT PARTITION
/dev/nvmeXXp3
Size: +364G
Type: Linux x86-64 root

#######################
## FORMAT PARTITIONS ##
#######################

# FORMAT PARTITION 1
mkfs.fat -F32 /dev/nvmeXXp1
# FORMAT PARTITION 2
mkswap /dev/nvmeXXp2
# FORMAT PARTITION 3
mkfs.ext4 /dev/nvmeXXp3

########################################
## GET THE UUID OF THE SWAP PARTITION ##
########################################

# *ONLY* IF NEEDED TRY THIS COMMAND
# ls -lha /dev/disk/by-uuid

pacman -S core nano

#################
## MOUNT DISKS ##
#################

# MOUNT PARTITION 3
mount /dev/nvmeXXp3 /mnt
# MOUNT PARTITION 1
mount --mkdir /dev/nvmeXXp1 /mnt/boot
# MOUNT PARTITION 2
mount /dev/nvmeXXp2 /swap
# VERIFY MOUNTS
lsblk

###############################
## INSTALL SOFTWARE ON MOUNT ##
###############################

pacstrap -K /mnt base base-devel efibootmgr grub linux linux-headers linux-firmware nano NetworkManager

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash

ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime

hwclock --systohc

locale-gen

echo 'LANG=en_US.UTF-8' > /etc/locale.conf

echo 'NAME-OF-COMPUTER' > /etc/hostname

mkinitcpio -P

echo '127.0.1.1 localhost.localdomain NAME-OF-COMPUTER' >> /etc/hosts

systemctl enable NetworkManager

passwd root

## THE OFFICIAL GUIDE SAYS YOU CAN REBOOT AT THIS POINT

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
pacman -S pulseaudio pulseaudio-alsa xorg xorg-xinit xorg-server gnome lightdm lightdm-gtk-greeter nvidia virtualbox-guest-utils

# LOGIN TO GNOME DESKTOP
sudo systemctl start gdm.service
sudo systemctl enable gdm.service
sudo reboot

sudo pacman -S firefox vlc leafpad
