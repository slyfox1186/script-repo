#!/usr/bin/env bash

# Mount Network Drive
mnd() (
    local drive_ip="192.168.2.2" drive_name="Cloud" mount_point="m"
    local user_choice

    is_mounted() {
        mountpoint -q "/$mount_point"
    }

    mount_drive() {
        if is_mounted; then
            echo "Drive '$drive_name' is already mounted at $mount_point."
        else
            mkdir -p "/$mount_point"
            mount -t drvfs "\\\\$drive_ip\\$drive_name" "/$mount_point" &&
                echo "Drive '$drive_name' mounted successfully at $mount_point."
        fi
    }

    unmount_drive() {
        if is_mounted; then
            umount "/$mount_point" &&
                echo "Drive '$drive_name' unmounted successfully from $mount_point."
        else
            echo "Drive '$drive_name' is not mounted."
        fi
    }

    echo "Select an option:"
    echo "1) Mount the network drive"
    echo "2) Unmount the network drive"
    read -r -p "Enter your choice (1/2): " user_choice

    case $user_choice in
        1) mount_drive ;;
        2) unmount_drive ;;
        *) echo "Invalid choice. Please enter 1 or 2." ;;
    esac
)
