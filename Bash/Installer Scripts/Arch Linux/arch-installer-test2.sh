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
PARTITION1_SIZE="+550M"
PARTITION2_SIZE="+2G"
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

# Disk setup function
setup_disk() {
    echo "Initializing disk setup..."

    # Initialize partition types for selection
    declare -A PARTITION_TYPES=(
        [1]="EFI System"
        [2]="MBR Partition Scheme"
        [3]="Intel Fast Flash"
        [4]="BIOS Boot"
        [5]="Sony Boot Partition"
        [6]="Lenovo Boot Partition"
        [7]="Microsoft Reserved"
        [8]="Microsoft Basic Data"
        [9]="Microsoft LDM Metadata"
        [10]="Microsoft LDM Data"
        [11]="Microsoft Recovery"
        [12]="HP-UX Data"
        [13]="HP-UX Service"
        [14]="Linux Filesystem"
        [15]="Linux Extended"
        [16]="Linux LVM"
        [17]="Linux Reserved"
        [18]="Linux RAID"
        [19]="Linux Swap"
        [20]="Linux Filesystem"
        [21]="Linux Server Data"
        [22]="Linux Root (x86)"
        [23]="Linux Root (x86-64)"
        [24]="Linux Root (ARM)"
        [25]="Linux Root (ARM-64)"
        [26]="Linux Root (IA-64)"
        [27]="Linux Reserved"
        [82]="Linux Swap"
        [83]="Linux"
        [86]="NT FAT16"
        [87]="NTFS"
        [88]="Linux Plaintext"
        [89]="Linux LVM"
        [90]="Linux RAID"
        [91]="Linux Extended"
        [92]="Linux Swap"
        [93]="Hidden Linux"
        [94]="Linux Reserved"
        [95]="Linux RAID Autodetect"
        [98]="Linux Swap"
        [99]="Linux LVM"
    )

    # Prompt for the disk to use
    read -p "Enter the disk to partition (e.g., /dev/sda): " DISK

    # Prompt for the number of partitions
    read -p "Enter the total number of partitions: " PARTITION_COUNT
    while ! [[ "$PARTITION_COUNT" =~ ^[0-9]+$ ]] || [ "$PARTITION_COUNT" -lt 2 ]; do
        echo "Please enter a valid number of partitions (at least 2)."
        read -p "Enter the total number of partitions: " PARTITION_COUNT
    done

    echo "Setting up disk with GPT partition table..."
    parted -s "$DISK" mklabel gpt

    local start=1
    local end=0
    local disk_parts=()

    # Function to convert GB to MB and strip non-numeric characters
    convert_size() {
        local input_size="$1"
        local numeric_size="${input_size//[!0-9.]/}"
        if [[ "$input_size" =~ G|g ]]; then
            numeric_size=$(echo "$numeric_size * 1024" | bc | awk '{print int($1+0.5)}')
        elif [[ "$input_size" =~ M|m ]]; then
            numeric_size=$(echo "$numeric_size" | awk '{print int($1+0.5)}')
        fi
        echo "$numeric_size"
    }

    # Handle all partitions dynamically based on user input
    for (( i=1; i <= PARTITION_COUNT; i++ )); do
        local input_size type label
        read -p "Enter SIZE for partition $i (e.g., 500M or 2G): " input_size
        local size=$(convert_size "$input_size")
        end=$(($start + size))

        if [ "$i" -ne "$PARTITION_COUNT" ]; then  # Last partition uses all remaining space
            echo "Available partition types:"
            for key in "${!PARTITION_TYPES[@]}"; do
                echo "$key ${PARTITION_TYPES[$key]}"
            done
            read -p "Enter the partition type number for partition $i: " type
            label=${PARTITION_TYPES[$type]}
            parted -s "$DISK" mkpart primary "$label" "${start}MiB" "${end}MiB"
        else
            parted -s "$DISK" mkpart primary ext4 "${start}MiB" 100%
        fi

        disk_parts+=("${DISK}${i}")
        start=$end
    done

    # Creating filesystems
    echo
    log "Creating filesystems..."
    mkfs.fat -F32 ${disk_parts[0]}   # Assuming the first partition is EFI
    mkswap ${disk_parts[1]}         # Assuming the second partition is SWAP
    for (( j=2; j < ${#disk_parts[@]}; j++ )); do
        mkfs.ext4 ${disk_parts[$j]}  # Assuming the rest are ext4
    done

    echo "Partitions created and formatted successfully."
}

# Partition mounting
mount_partitions() {
    log "Enabling swap and mounting partitions..."
    swapon "$DISK2"
    
    if [[ "$PARTITION_COUNT" -ne 3 ]]; then
        echo "$PARTITION_COUNT"
        echo
        read -p "Press enter to exit."
        exit
    fi
    
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
    local PACKAGES="base efibootmgr grub linux linux-headers linux-firmware nano networkmanager reflector sudo" # Package list
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

# Grub installation and configuration
grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg
log "GRUB installed."

mkdir -p /boot/efi/EFI/BOOT

cp -f /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
log "GRUB bootloader copied to EFI directory."

echo 'bcf boot add 1 fs0:\EFI\GRUB\grubx64.efi "Arch Linux Bootloader"' > /boot/efi/startup.sh
echo 'exit' >> /boot/efi/startup.sh
log "UEFI startup script created."

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
