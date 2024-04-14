#!/usr/bin/env bash

GREEN='\033[0;32m'
NC='\033[0m'

# Verbose logging function
log() {
    echo -e "${GREEN}[LOG $(date +'%R:%S')]${NC} $1"
}

# Variables
USERNAME="" # Non-root username
USER_PASSWORD="" # Non-root user password
ROOT_PASSWORD="" # Root password
COMPUTER_NAME=""
TIMEZONE="US/Eastern"
DISK="" # Disk to install Arch Linux on (e.g., /dev/sda or /dev/nvme0n1)

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
    echo "  -d DISK           Set the target disk (e.g., /dev/sdX or /dev/nvmeXn1)"
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
    local var_name="$1"
    local prompt="$2"
    local var_value=$(eval echo \$$var_name)
    while [[ -z "$var_value" ]]; do
        read -p "$prompt: " var_value
        eval $var_name="$var_value"
    done
}

prompt_variable USERNAME "Enter the non-root username"
prompt_variable USER_PASSWORD "Enter the non-root user password"
prompt_variable ROOT_PASSWORD "Enter the root password"
prompt_variable COMPUTER_NAME "Enter the computer name"
prompt_variable DISK "Enter the target disk (e.g., /dev/sda or /dev/nvme0n1)"

# Determine disk partition naming convention
if [[ "$DISK" == *"nvme"* ]]; then
    DISK1="${DISK}p1"
    DISK2="${DISK}p2"
    DISK3="${DISK}p3"
else
    DISK1="${DISK}1"
    DISK2="${DISK}2"
    DISK3="${DISK}3"
fi

# Disk setup
setup_disk() {
    local disk_parts=("$DISK1" "$DISK2" "$DISK3")
    
    # Prompt for partition count
    read -p "Enter the number of partitions (minimum 3): " PARTITION_COUNT
    while [[ "$PARTITION_COUNT" -lt 3 ]]; do
        echo "The minimum number of partitions is 3."
        read -p "Enter the number of partitions (minimum 3): " PARTITION_COUNT
    done

    # Set partition 1 as GPT and EFI
    echo "Partition 1 will be set as GPT and EFI."
    read -p "Enter partition 1 SIZE (e.g., 550M): " PARTITION1_SIZE

    # Set partition 2 as swap and prompt for SIZE
    echo "Partition 2 will be set as swap."
    read -p "Enter partition 2 SIZE (e.g., 2G): " PARTITION2_SIZE

    # Prompt for sizes and types of remaining partitions (excluding the last one)
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

    # Set the last partition as root (x86-64)
    echo "The last partition will be set as Linux x86-64 root and use the remaining disk space."

    # Partition the disk
    echo
    log "Partitioning disk $DISK..."
    parted -s "$DISK" mklabel gpt

    if [[ "$DISK" == *"nvme"* ]]; then
        parted -s "$DISK" mkpart primary fat32 1 $(echo "$PARTITION1_SIZE" | sed 's/[^0-9]*//g')
        parted -s "$DISK" set 1 esp on
        parted -s "$DISK" mkpart primary linux-swap $(echo "$PARTITION1_SIZE" | sed 's/[^0-9]*//g') $(echo "$(echo "$PARTITION2_SIZE" | sed 's/[^0-9]*//g') * 1024" | bc)
        
        local start=$(echo "$(echo "$PARTITION2_SIZE" | sed 's/[^0-9]*//g') * 1024" | bc)
        for ((i=0; i<${#PARTITION_SIZES[@]}; i++)); do
            local SIZE=$(echo "$(echo "${PARTITION_SIZES[i]}" | sed 's/[^0-9]*//g') * 1024" | bc)
            local end=$((start + SIZE))
            parted -s "$DISK" mkpart primary $start $end
            local type=${PARTITION_TYPES[i]}
            case $type in
                1) parted -s "$DISK" set $((i+3)) esp on ;;
                2) parted -s "$DISK" set $((i+3)) bios_grub on ;;
                4) parted -s "$DISK" set $((i+3)) boot on ;;
                19) parted -s "$DISK" set $((i+3)) swap on ;;
            esac
            start=$end
        done
        
        # Create the final partition with the remaining space and set the partition type to Linux filesystem
        parted -s "$DISK" mkpart primary $start 100%
        parted -s "$DISK" set $PARTITION_COUNT 20
    else
        parted -s "$DISK" mkpart primary fat32 1 $(echo "$PARTITION1_SIZE" | sed 's/[^0-9]*//g')
        parted -s "$DISK" set 1 esp on
        parted -s "$DISK" mkpart primary linux-swap $(echo "$PARTITION1_SIZE" | sed 's/[^0-9]*//g') $(echo "$(echo "$PARTITION2_SIZE" | sed 's/[^0-9]*//g') * 1024" | bc)
        
        local start=$(echo "$(echo "$PARTITION2_SIZE" | sed 's/[^0-9]*//g') * 1024" | bc)
        for ((i=0; i<${#PARTITION_SIZES[@]}; i++)); do
            local SIZE=$(echo "$(echo "${PARTITION_SIZES[i]}" | sed 's/[^0-9]*//g') * 1024" | bc)
            local end=$((start + SIZE))
            parted -s "$DISK" mkpart primary $start $end
            local type=${PARTITION_TYPES[i]}
            case $type in
                1) parted -s "$DISK" set $((i+3)) esp on ;;
                2) parted -s "$DISK" set $((i+3)) bios_grub on ;;
                4) parted -s "$DISK" set $((i+3)) boot on ;;
                19) parted -s "$DISK" set $((i+3)) swap on ;;
            esac
            start=$end
        done
        
        # Create the final partition with the remaining space and set the partition type to Linux filesystem
        parted -s "$DISK" mkpart primary $start 100%
        parted -s "$DISK" set $PARTITION_COUNT 23
    fi

    # Make filesystems
    echo
    log "Creating filesystems..."
    if [[ "$DISK" == *"nvme"* ]]; then
        mkfs.fat -F32 "${DISK}p1"
        mkswap "${DISK}p2"
        mkfs.ext4 "${DISK}p${PARTITION_COUNT}"
    else
        mkfs.fat -F32 "${DISK}1"
        mkswap "${DISK}2"
        mkfs.ext4 "${DISK}${PARTITION_COUNT}"
    fi
}

# Partition mounting
mount_partitions() {
    log "Enabling swap and mounting partitions..."
    swapon "$DISK2"
    
    if [[ "$DISK" == *"nvme"* ]]; then
        mount "${DISK}p${PARTITION_COUNT}" /mnt
        mount --mkdir "${DISK}p1" /mnt/boot/efi
    else
        mount "${DISK}${PARTITION_COUNT}" /mnt
        mount --mkdir "${DISK}1" /mnt/boot/efi
    fi
}

# Prompt for loadkeys
prompt_loadkeys() {
    local loadkeys_value
    while [[ -z "$loadkeys_value" ]]; do
        clear
        read -p "Enter the value for loadkeys (press 'l' to list available options or Enter to continue): " loadkeys_value
        if [[ "$loadkeys_value" == "l" ]]; then
            echo "Available keymaps:"
            tempfile=$(mktemp)
            localectl list-keymaps > "$tempfile"
            more "$tempfile"
            rm "$tempfile"
            read -p "Enter the value for loadkeys: " loadkeys_value
            if [[ -n "$loadkeys_value" ]]; then
                loadkeys "$loadkeys_value"
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
    local PACKAGES="base linux linux-headers linux-firmware nano networkmanager reflector sudo" # Updated package list
    echo
    log "Installing essential packages..."
    echo "Current package list: $PACKAGES"
    echo
    read -p "Enter to continue or, add additional packages to install (spaced separated) with the ability to remove a package by prefixing it with a minus sign '-': " add_pkgs
    for package in $add_pkgs; do
        if [[ "$package" == -* ]]; then
            PACKAGES=$(echo "$PACKAGES" | sed "s/${package#-}//g")
        else
            PACKAGES+=" $package"
        fi
    done
    pacstrap /mnt $PACKAGES
}

# Chroot configuration
configure_chroot() {
    log "Entering chroot to configure system..."
    arch-chroot /mnt /bin/bash <<EOF
# Set timezone and hardware clock
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
log "Timezone set to $TIMEZONE."

# Localization
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
log "Locale set."

# Network configuration
echo "$COMPUTER_NAME" > /etc/hostname
mkinitcpio -P
echo "127.0.1.1 myarch.localdomain $COMPUTER_NAME" >> /etc/hosts
log "Network configuration complete."

# Set root password
echo root:"$ROOT_PASSWORD" | chpasswd
log "Root password set."

# Create a new user with user variables
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
log "User $USERNAME created."

# Enable sudo for wheel group
echo "" >> /etc/sudoers
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
log "Sudo privileges granted to the wheel group."

# Systemd-boot installation and configuration
bootctl --path=/boot/efi install
mkdir -p /boot/efi/loader/entries
echo "default arch.conf" > /boot/efi/loader/loader.conf
echo "timeout 4" >> /boot/efi/loader/loader.conf
echo "title   Arch Linux" > /boot/efi/loader/entries/arch.conf
echo "linux   /vmlinuz-linux" >> /boot/efi/loader/entries/arch.conf
echo "initrd  /initramfs-linux.img" >> /boot/efi/loader/entries/arch.conf
echo "options root=PARTUUID=$(blkid -s PARTUUID -o value ${DISK}p${PARTITION_COUNT}) rw" >> /boot/efi/loader/entries/arch.conf
log "Systemd-boot installed and configured."

systemctl enable NetworkManager.service
log "NetworkManager service enabled."
systemctl start NetworkManager.service
log "NetworkManager service started."
EOF
}

# Prompt for unmounting partitions
prompt_umount() {
    local choice
    while true; do
        read -p "Do you want to unmount all partitions? (y/n): " choice
        case "$choice" in
            [yY]*|[yY][eE][sS]*)
                log "Unmounting all partitions..."
                umount -R /mnt
                swapoff -a
                break
                ;;
            [nN]*|[nN][oO]*)
                break
                ;;
            *)  echo "Invalid choice. Please enter 'y' or 'n'."
                sleep 4
                unset choice
                prompt_umount
                ;;
        esac
    done
}

# Prompt for reboot
prompt_reboot() {
    local choice
    echo
    while true; do
        read -p "Installation complete. Do you want to reboot now? (y/n): " choice
        case "$choice" in
            [yY]*|[yY][eE][sS]*)
                reboot
                break
                ;;
            [nN]*|[nN][oO]*)
                break
                exit
                ;;
            *)  echo "Invalid choice. Please enter 'y' or 'n'."
                sleep 4
                unset choice
                prompt_reboot
                ;;
        esac
    done
}

# Main script
main() {
    # Start installation
    log "Starting installation..."
    prompt_loadkeys
    timedatectl set-ntp true
    log "System clock synchronized."

    setup_disk
    mount_partitions
    install_packages
    
    # Generate fstab
    echo
    log "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab

    configure_chroot
    prompt_umount
    prompt_reboot
}

# Run the main script
main
