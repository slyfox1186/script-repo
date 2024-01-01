#!/usr/bin/env bash

clear

set -e

# Change as needed
disk=/dev/nvmeXn1p
username=
password=
computer_name=
country=US
region=Eastern

localectl set-keymap --no-convert us

timedatectl set-ntp true

#######################
## FORMAT PARTITIONS ##
#######################

# FORMAT PARTITION 1
mkfs.fat -F32 ${disk}1
# FORMAT PARTITION 2
mkswap ${disk}2
# FORMAT PARTITION 3
mkfs.ext4 ${disk}3

#################
## MOUNT DISKS ##
#################

# MOUNT PARTITION 3
mount ${disk}3 /mnt
# MOUNT PARTITION 1
mount --mkdir ${disk}1 /mnt/boot
# MOUNT PARTITION 2
swapon ${disk}2

###############################
## INSTALL SOFTWARE ON MOUNT ##
###############################

pacstrap -K /mnt base efibootmgr grub linux linux-headers linux-firmware networkmanager

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF

ln -sf /usr/share/zoneinfo/$country/$region /etc/localtime

hwclock --systohc

echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen

locale-gen

echo "$computer_name" > /etc/hostname

mkinitcpio -P

echo "127.0.1.1 localhost.localdomain $computer_name" >> /etc/hosts

systemctl enable NetworkManager

useradd -m -g users -G wheel -s /bin/bash $username

echo "$username:$password" | chpasswd

echo "root:$password" | chpasswd 

if [ ! -d /boot/efi ]; then
    mkdir -p /boot/efi
fi

mount ${disk}1 /boot/efi

grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi

grub-mkconfig -o  /boot/grub/grub.cfg

if [ ! -d /boot/efi/EFI/BOOT ]; then
    mkdir -p /boot/efi/EFI/BOOT
fi

cp -f /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

echo 'bcf boot add 1 fs0:\EFI\GRUB\grubx64.efi "Arch Linux Bootloader"' > /boot/efi/startup.sh
echo 'exit' >> /boot/efi/startup.sh
EOF

umount -R /mnt

printf "\n%s\n\n" 'The script has finished. Please reboot.'
