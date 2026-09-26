#!/usr/bin/env bash

## Write caching ##
wcache() {
    local choice

    lsblk
    echo
    read -r -p "Enter the drive id to turn off write caching (/dev/sdX w/o /dev/): " choice

    sudo hdparm -W 0 /dev/"$choice"
}
