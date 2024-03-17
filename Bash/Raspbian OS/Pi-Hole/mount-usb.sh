#!/usr/bin/env bash

clear

lsblk
echo
read -p 'Enter the mount path (/mnt): ' mpath
clear
fdisk -l
echo
read -p 'Please enter the usb device path (/dev/sda1): ' dpath
clear

case "$mpath" in
    ''      mnt_path='/mnt';;
    *)      mnt_path="$mpath"
esac

sudo mkdir -p "$mnt_path"

sudo mount "$dpath" "$mnt_path" -o auto exec,nofail,user,uid=pi,gid=pi,errors=remount-ro 0 0

alias umount_usb="sudo umount $mnt_path"

clear
printf "%s\n%s\n\n" \
    "Remember to remove the USB execute the command \"sudo umount $mnt_path\"" \
    "To make things easier you can use the alias this script created named \"umount_usb\""

