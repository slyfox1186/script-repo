#!/usr/bin/env bash

set -euo pipefail

clear
lsblk
echo

read -rp 'Enter the mount path [/mnt]: ' mpath
mnt_path="${mpath:-/mnt}"

clear
sudo fdisk -l
echo

read -rp 'Enter the USB device path (e.g., /dev/sda1): ' dpath

if [[ -z "$dpath" ]]; then
    echo "Error: Device path cannot be empty."
    exit 1
fi

if [[ ! -b "$dpath" ]]; then
    echo "Error: '$dpath' is not a valid block device."
    exit 1
fi

sudo mkdir -p "$mnt_path"

current_user="$(id -un)"
current_group="$(id -gn)"

sudo mount "$dpath" "$mnt_path" -o auto,exec,nofail,user,"uid=$current_user,gid=$current_group",errors=remount-ro

clear
printf "%s\n\n" "USB device mounted at: $mnt_path"
printf "%s\n" "To unmount, run: sudo umount \"$mnt_path\""
