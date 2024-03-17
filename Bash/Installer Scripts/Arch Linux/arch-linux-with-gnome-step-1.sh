#!/Usr/bin/env bash
clear

# Verbose logging function
log() {
    echo "[LOG $(date +'%m-%d-%Y %H:%M:%S')] $1"
}

# Variables
log "Setting up variables..."
USERNAME="" # Non-root username
USER_PASSWORD="" # Non-root user password
ROOT_PASSWORD="" # Root password
COMPUTER_NAME=""
TIMEZONE="US/Eastern"

# Disk variables
log "Setting up disk variables..."
DISK="/dev/nvmeXn1" # Adjust as necessary
DISK1="$DISKp1"
DISK2="$DISKp2"
DISK3="$DISKp3"

# Start installation
log "Starting installation..."
loadkeys us # Set keyboard layout
log "Keyboard layout set."
timedatectl set-ntp true # Ensure the system clock is accurate
log "System clock synchronized."

# Disk partitioning with fdisk
log "Partitioning disk $DISK..."
(
echo g     # Create a new empty gpt partition table
echo n     # Add a new partition (efi)
echo 1     # Partition number
echo       # First sector (accept default: 1)
echo +550M # Last sector (accept default, +550m)
echo t     # Change partition type
echo 1     # Partition type efi
echo n     # Add a new partition (swap)
echo 2     # Partition number
echo       # First sector (accept default)
echo +2G   # Last sector (accept default, +2g)
echo t     # Change partition type
echo 2     # Select partition
echo 19    # Partition type linux swap
echo n     # Add new partition (linux filesystem)
echo 3     # Partition number
echo       # First sector (accept default)
echo       # Last sector (accept default, remaining space)
echo t     # Change partition type
echo 3     # Select partition
echo 23    # Partition type linux root (x86_64)
echo w     # Write changes
) | fdisk $DISK

# Wait for the disk to settle
log "Waiting for the disk to settle..."
sleep 5

# Making filesystems
log "Creating filesystems..."
mkfs.fat -F32 $DISK1
mkswap $DISK2
mkfs.ext4 $DISK3

# Enable swap and mount partitions
log "Enabling swap and mounting partitions..."
swapon $DISK2
mount $DISK3 /mnt
mount --mkdir $DISK1 /mnt/boot/efi

# Install essential packages
log "Installing essential packages..."
pacstrap -K /mnt base efibootmgr grub linux linux-headers linux-firmware networkmanager

# Generate fstab
log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot and setup
log "Entering chroot to configure system..."
arch-chroot /mnt /bin/bash <<EOF
# Set timezone and hardware clock
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
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
echo root:$ROOT_PASSWORD | chpasswd
log "Root password set."

# Create a new user with user variables
useradd -m -G wheel -s /bin/bash $USERNAME
echo $USERNAME:$USER_PASSWORD | chpasswd
log "User $USERNAME created."

# Enable sudo for wheel group
echo "" >> /etc/sudoers
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
log "Sudo privileges granted to the wheel group."

# Grub installation and configuration
grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg
log "GRUB installed."

if [ ! -d /boot/efi/EFI/BOOT ]; then
    mkdir -p /boot/efi/EFI/BOOT
fi
cp -f /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
log "GRUB bootloader copied to EFI directory."

echo 'bcf boot add 1 fs0:\EFI\GRUB\grubx64.efi "Arch Linux Bootloader"' > /boot/efi/startup.nsh
echo 'exit' >> /boot/efi/startup.sh
log "UEFI startup script created."

EOF

# Unmount all partitions
log "Unmounting all partitions..."
umount -R /mnt
swapoff -a

# Installation complete
log "Arch Linux installation complete. You can reboot now."
