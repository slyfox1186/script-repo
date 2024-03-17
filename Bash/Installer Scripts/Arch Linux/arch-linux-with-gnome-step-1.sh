#!/Usr/bin/env bash
clear

log() {
    echo "[LOG $(date +'%m-%d-%Y %H:%M:%S')] $1"
}

log "Setting up variables..."
COMPUTER_NAME=""
TIMEZONE="US/Eastern"

log "Setting up disk variables..."
DISK1="$DISKp1"
DISK2="$DISKp2"
DISK3="$DISKp3"

log "Starting installation..."
log "Keyboard layout set."
log "System clock synchronized."

log "Partitioning disk $DISK..."
(
) | fdisk $DISK

log "Waiting for the disk to settle..."
sleep 5

log "Creating filesystems..."
mkfs.fat -F32 $DISK1
mkswap $DISK2
mkfs.ext4 $DISK3

log "Enabling swap and mounting partitions..."
swapon $DISK2
mount $DISK3 /mnt
mount --mkdir $DISK1 /mnt/boot/efi

log "Installing essential packages..."
pacstrap -K /mnt base efibootmgr grub linux linux-headers linux-firmware networkmanager

log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

log "Entering chroot to configure system..."
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
log "Timezone set to $TIMEZONE."

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
log "Locale set."

echo "$COMPUTER_NAME" > /etc/hostname
mkinitcpio -P
echo "127.0.1.1 myarch.localdomain $COMPUTER_NAME" >> /etc/hosts
log "Network configuration complete."

echo root:$ROOT_PASSWORD | chpasswd
log "Root password set."

useradd -m -G wheel -s /bin/bash $USERNAME
echo $USERNAME:$USER_PASSWORD | chpasswd
log "User $USERNAME created."

echo "" >> /etc/sudoers
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
log "Sudo privileges granted to the wheel group."

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

log "Unmounting all partitions..."
umount -R /mnt
swapoff -a

log "Arch Linux installation complete. You can reboot now."
