#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo 'This script must be run as root' 
   exit 1
fi

# Set Variables (You must edit these)
# WARNING! It is considered bad practice to store passwords in a file... MAKE SURE you change these after you log into Arch Linux!
user_name='username'
user_password='password'
root_password='password'
computer_name='name'

# Update the system clock
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
1

+512M
t
1
n
2

+1.8TB
t
23
n
3

+2G
t
19
w
EOF

# Format the partitions
regex_str='^\/dev\/sd'
if [[ ! $drive_path =~ $regex_str ]]; then
    mount "${drive_path}1p2" /mnt
    mount --mkdir "${drive_path}1p1" /mnt/efi
    swapon "${drive_path}1p3"
else
    mount "${drive_path}2" /mnt
    mount --mkdir "${drive_path}1" /mnt/efi
    swapon "${drive_path}3"
fi
