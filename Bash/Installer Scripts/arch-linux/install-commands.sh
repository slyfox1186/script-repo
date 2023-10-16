#!/usr/bin/env bash

clear

################
## LIST DISKS ##
################

fdisk -l
fdisk /dev/nvmeXX

####################
## PARTITION DISK ##
####################

cfdisk /dev/nvmeXXX
# SET EFI PARTITION
/dev/nvmeXXp1
Size: +512M
Type: EFI
# SET EFI PARTITION
/dev/nvmeXXp2
Size: +460GB
Type: Linux Filesystem
# SET EFI PARTITION
/dev/nvmeXXp3
Size: +512M
Type: Linux Filesystem
# SET EFI PARTITION
/dev/nvmeXXp4
Size: +32GB
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
echo 'UUID=xxxxxx-xx-x-x-x-x-x none swap defaults 0 0' > /etc/fstab

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

pacstrap -i /mnt base base-devel linux linux-headers nano

genfstab -U -p /mnt  >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash

nano /etc/locale.gen
  >> FIND and uncomment the line "#en_US.UTF-8 UTF-8"


