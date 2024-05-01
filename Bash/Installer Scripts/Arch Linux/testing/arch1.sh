#!/usr/bin/env bash

GREEN='\033[0;32m'
NC='\033[0m'

# Verbose logging function
log() {
    echo -e "${GREEN}[LOG]${NC} $1"
}

# Variables with placeholders for command line arguments
USERNAME=""
USER_PASSWORD=""
ROOT_PASSWORD=""
COMPUTER_NAME=""
TIMEZONE="US/Eastern"  # Default value for TIMEZONE
DISK=""

# Helper function to prompt for missing variables
prompt_variable() {
    local var_name="$1"
    local prompt_msg="$2"
    local var_value
    eval var_value=\$$var_name

    while [[ -z "$var_value" ]]; do
        read -p "$prompt_msg: " var_value
        if [[ -z "$var_value" ]]; then
            echo "This is a required field. Please enter a value."
        else
            eval $var_name='$var_value'
        fi
    done
}

# Check and prompt for each required variable
[[ -z "$USERNAME" ]] && prompt_variable USERNAME "Enter the non-root username"
[[ -z "$USER_PASSWORD" ]] && prompt_variable USER_PASSWORD "Enter the non-root user password"
[[ -z "$ROOT_PASSWORD" ]] && prompt_variable ROOT_PASSWORD "Enter the root password"
[[ -z "$COMPUTER_NAME" ]] && prompt_variable COMPUTER_NAME "Enter the computer name"
[[ -z "$DISK" ]] && prompt_variable DISK "Enter the target disk (e.g., sdX or nvmeXn1)"

# Append '/dev/' to DISK for internal use
FULL_DISK_PATH="/dev/$DISK"

# Partition variables
PARTITION_COUNT=3
PARTITION1_SIZE="500M"
PARTITION2_SIZE="2G"
PARTITION_SIZES=()
PARTITION_TYPES=()

# Help function
help() {
    echo "Arch Linux Installation Script"
    echo "This script automates the installation of Arch Linux."
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -u USERNAME       Set the non-root username"
    echo "  -p USER_PASSWORD  Set the non-root user password"
    echo "  -r ROOT_PASSWORD  Set the root password"
    echo "  -c COMPUTER_NAME  Set the computer name"
    echo "  -t TIMEZONE       Set the timezone (default: US/Eastern)"
    echo "  -d DISK           Set the target disk (e.g., sdX or nvmeXn1)"
    echo "  -h                Display this help message"
    echo
    echo "Examples:"
    echo "  $0 -u john -p password123 -r rootpass -c myarch -t Europe/London -d /dev/sda"
    echo "  $0 -u jane -p pass456 -r rootpass789 -c janepc -d /dev/nvme0n1"
    exit 0
}

# Parse command line arguments
while getopts ":u:p:r:c:t:d:h" opt; do
    case "$opt" in
        u) USERNAME="$OPTARG" ;;
        p) USER_PASSWORD="$OPTARG" ;;
        r) ROOT_PASSWORD="$OPTARG" ;;
        c) COMPUTER_NAME="$OPTARG" ;;
        t) TIMEZONE="$OPTARG" ;;
        d) DISK="$OPTARG" ;;
        h) help ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
        :) echo "Option -$OPTARG requires an argument." >&2; exit 1;;
    esac
done

# Prompt for missing variables
prompt_variable() {
    local prompt var_name var_value
    var_name="$1"
    prompt="$2"
    var_value=$(eval echo \$var_name)
    while [[ -z "$var_value" ]]; do
        read -p "$prompt: " var_value
        eval $var_name="$var_value"
    done
}

# Set values for the prompt_variable function
prompt_variable USERNAME "Enter the non-root username"
prompt_variable USER_PASSWORD "Enter the non-root user password"
prompt_variable ROOT_PASSWORD "Enter the root password"
prompt_variable COMPUTER_NAME "Enter the computer name"
prompt_variable DISK "Enter the target disk (e.g., /dev/sda or /dev/nvme0n1)"

# Determine disk partition naming convention
if [[ "$FULL_DISK_PATH" == *"nvme"* ]]; then
    DISK1="${FULL_DISK_PATH}p1"
    DISK2="${FULL_DISK_PATH}p2"
    DISK3="${FULL_DISK_PATH}p3"
else
    DISK1="${FULL_DISK_PATH}1"
    DISK2="${FULL_DISK_PATH}2"
    DISK3="${FULL_DISK_PATH}3"
fi

# Partition the disk
setup_disk() {
    local disk_parts end SIZE start type
    disk_parts=("$DISK1" "$DISK2" "$DISK3")

    read -p "Enter the number of partitions (minimum 3): " PARTITION_COUNT
    while [[ "$PARTITION_COUNT" -lt 3 ]]; do
        echo "The minimum number of partitions is 3."
        read -p "Enter the number of partitions (minimum 3): " PARTITION_COUNT
    done

    # Store the default partition size set at the top of the script in another
    # variable in case the user wants to just hit enter and use the default value 
    DEFAULT_PARTITION1_SIZE="$PARTITION1_SIZE"
    echo "Partition 1 will be set as GPT and EFI."
    read -p "Enter partition 1 size or hit enter to use the default value (default: 500M): " PARTITION1_SIZE

    [[ -z "$PARTITION1_SIZE" ]] && PARTITION1_SIZE="$DEFAULT_PARTITION1_SIZE"

    # Store the default partition size set at the top of the script in another
    # variable in case the user wants to just hit enter and use the default value
    DEFAULT_PARTITION2_SIZE="$PARTITION2_SIZE"
    echo "Partition 2 will be set as swap."
    read -p "Enter partition 2 size or hit enter to use the default value (default: 2G): " PARTITION2_SIZE

    [[ -z "$PARTITION2_SIZE" ]] && PARTITION2_SIZE="$DEFAULT_PARTITION2_SIZE"

    for ((i=3; i<PARTITION_COUNT; i++)); do
        read -p "Enter SIZE for partition $i: " SIZE
        PARTITION_SIZES+=("$SIZE")

        echo "Available partition types:"
        echo
        echo "1 EFI System"
        echo "2 MBR Partition Scheme"
        echo "3 Intel Fast Flash"
        echo "4 BIOS Boot"
        echo "5 Sony Boot Partition"
        echo "6 Lenovo Boot Partition"
        echo "7 Microsoft Reserved"
        echo "8 Microsoft Basic Data"
        echo "9 Microsoft LDM Metadata"
        echo "10 Microsoft LDM Data"
        echo "11 Microsoft Recovery"
        echo "12 HP-UX Data"
        echo "13 HP-UX Service"
        echo "14 Linux Filesystem"
        echo "15 Linux Extended"
        echo "16 Linux LVM"
        echo "17 Linux Reserved"
        echo "18 Linux RAID"
        echo "19 Linux Swap"
        echo "20 Linux Filesystem"
        echo "21 Linux Server Data"
        echo "22 Linux Root (x86)"
        echo "23 Linux Root (x86-64)"
        echo "24 Linux Root (ARM)"
        echo "25 Linux Root (ARM-64)"
        echo "26 Linux Root (IA-64)"
        echo "27-81 Linux Reserved"
        echo "82 Linux Swap"
        echo "83 Linux"
        echo "84-85 Linux Extended"
        echo "86 NT FAT16"
        echo "87 NTFS"
        echo "88 Linux Plaintext"
        echo "89 Linux LVM"
        echo "90 Linux RAID"
        echo "91 Linux Extended"
        echo "92 Linux Swap"
        echo "93 Hidden Linux"
        echo "94 Linux Reserved"
        echo "95-97 Linux RAID Autodetect"
        echo "98 Linux Swap"
        echo "99 Linux LVM"
        read -p "Enter the partition type number for partition $i: " type
        PARTITION_TYPES+=("$type")
    done

    echo "The last partition will be set as Linux x86-64 root and use the remaining disk space."

    echo
    log "Partitioning disk $FULL_DISK_PATH..."
    parted -s "$FULL_DISK_PATH" mklabel gpt

    parted -s "$FULL_DISK_PATH" mkpart primary fat32 1 $(echo "$PARTITION1_SIZE" | sed 's/[^0-9]*//g')
    parted -s "$FULL_DISK_PATH" set 1 esp on
    parted -s "$FULL_DISK_PATH" mkpart primary linux-swap $(echo "$PARTITION1_SIZE" | sed 's/[^0-9]*//g') $(echo "$(echo "$PARTITION2_SIZE" | sed 's/[^0-9]*//g') * 1024" | bc)

    start=$(echo "$(echo "$PARTITION2_SIZE" | sed 's/[^0-9]*//g') * 1024" | bc)
    for ((i=0; i<${#PARTITION_SIZES[@]}; i++)); do
        SIZE=$(echo "$(echo "${PARTITION_SIZES[i]}" | sed 's/[^0-9]*//g') * 1024" | bc)
        end=$((start + SIZE))
        parted -s "$FULL_DISK_PATH" mkpart primary $start $end
        type=${PARTITION_TYPES[i]}
        case $type in
            1) parted -s "$FULL_DISK_PATH" set $((i+3)) esp on ;;
            2) parted -s "$FULL_DISK_PATH" set $((i+3)) bios_grub on ;;
            4) parted -s "$FULL_DISK_PATH" set $((i+3)) boot on ;;
            19) parted -s "$FULL_DISK_PATH" set $((i+3)) swap on ;;
        esac
        start=$end
    done

    parted -s "$FULL_DISK_PATH" mkpart primary $start 100%
    parted -s "$FULL_DISK_PATH" set $PARTITION_COUNT 23

    echo
    log "Creating filesystems..."

    mkfs.fat -F32 "$DISK1"
    mkswap "$DISK2"
    mkfs.ext4 "${DISK}${PARTITION_COUNT}"
}

# Mount the partitions
mount_partitions() {
    log "Enabling swap and mounting partitions..."
    swapon "$DISK2"

    mount "${DISK}${PARTITION_COUNT}" /mnt
    mount --mkdir "$DISK1" /mnt/boot/efi
}

# Prompt for loadkeys
prompt_loadkeys() {
    local loadkeys_value
    while [[ -z "$loadkeys_value" ]]; do
        read -p "Enter the value for loadkeys (press 'l' to list available options): " loadkeys_value
        if [[ "$loadkeys_value" == "l" ]]; then
            echo "Available keymaps:"
            tempfile=$(mktemp)
            localectl list-keymaps > "$tempfile"
            more "$tempfile"
            rm "$tempfile"
            read -p "Enter the value for loadkeys: " loadkeys_value
            if [[ -n "$loadkeys_value" ]]; then
                loadkeys "$loadkeys_value"
            else
                echo "You must enter a value to continue. Press l to get a list of available options."
                echo
                read -p "Press enter to try again."
                prompt_loadkeys
            fi
        elif [[ -n "$loadkeys_value" ]]; then
            loadkeys "$loadkeys_value"
        else
            break
        fi
    done
}

# Package installation
install_packages() {
    local PACKAGES
    PACKAGES="base efibootmgr linux linux-firmware linux-headers nano networkmanager os-prober reflector sudo"
    echo
    log "Installing essential packages..."
    echo "Current package list: $PACKAGES"
    echo
    read -p "Enter to continue or, add additional packages to install (spaced separated) with the ability to remove a package by prefixing it with a minus sign '-': " add_pkgs
    for pkgs in $add_pkgs; do
        if [[ "$package" == -* ]]; then
            PACKAGES=$(echo "$PACKAGES" | sed "s/${pkgs#-}//g")
        else
            PACKAGES+=" $package"
        fi
    done
    pacstrap -K /mnt $PACKAGES
}

# Create the fstab file in Arch Linux /etc
generate_fstab() {
    echo
    log "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Use a heredoc to execute commands using the arch-chroot command
configure_chroot() {
    log "Configuring installed system..."

    arch-chroot /mnt /bin/bash -c "
        ln -sf '/usr/share/zoneinfo/$TIMEZONE' /etc/localtime
        hwclock --systohc

        echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
        locale-gen
        echo 'LANG=en_US.UTF-8' > /etc/locale.conf

        echo '$COMPUTER_NAME' > /etc/hostname
        echo '127.0.1.1 myarch.localdomain $COMPUTER_NAME' >> /etc/hosts

        echo 'root:$ROOT_PASSWORD' | chpasswd

        useradd -m -G wheel -s /bin/bash '$USERNAME'
        echo '$USERNAME:$USER_PASSWORD' | chpasswd

        echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers

        # Copy kernel and initramfs to the ESP
        cp /boot/vmlinuz-linux /boot/efi/
        cp /boot/initramfs-linux.img /boot/efi/

        # Install and configure bootloader
        bootctl --path=/boot/efi install

        echo 'default arch' > /boot/efi/loader/loader.conf
        echo 'timeout 4' >> /boot/efi/loader/loader.conf
        echo 'editor 0' >> /boot/efi/loader/loader.conf

        echo 'title Arch Linux' > /boot/efi/loader/entries/arch.conf
        echo 'linux /vmlinuz-linux' >> /boot/efi/loader/entries/arch.conf
        echo 'initrd /initramfs-linux.img' >> /boot/efi/loader/entries/arch.conf

        # Enable NetworkManager so you have access to the internet after rebooting
        systemctl enable NetworkManager
        systemctl start NetworkManager.service
    "
}

# Fetch PARTUUID after exiting arch-chroot and export it to the arch.conf file
generate_and_set_partuuid() {
    PARTUUID=$(blkid -s PARTUUID -o value "${DISK}${PARTITION_COUNT}")
    echo "options root=PARTUUID=$PARTUUID rw" >> /mnt/boot/efi/loader/entries/arch.conf
}

# Prompt to unmount all of the partitions
prompt_umount() {
    local choice
    echo
    read -p "Installation complete. Do you want to unmount all partitions? (y/n): " choice
    case "$choice" in
        [yY]*|[yY][eE][sS]*)
            log "Unmounting all partitions..."
            umount -R /mnt
            swapoff -a
            ;;
        [nN]*|[nN][oO]*)
            ;;
        *)  unset choice
            prompt_umount
            ;;
    esac
}

# Prompt to reboot the pc
prompt_reboot() {
    local choice
    echo
    read -p "Do you want to reboot now? (y/n): " choice
    case "$choice" in
        [yY]*|[yY][eE][sS]*)
            reboot
            ;;
        [nN]*|[nN][oO]*)
            ;;
        *)  unset choice
            prompt_reboot
            ;;
    esac
}

# Start the installation
log "Starting installation..."
prompt_loadkeys
timedatectl set-ntp true
log "System clock synchronized."
setup_disk
mount_partitions
install_packages
generate_fstab
configure_chroot
generate_and_set_partuuid
prompt_umount
prompt_reboot
