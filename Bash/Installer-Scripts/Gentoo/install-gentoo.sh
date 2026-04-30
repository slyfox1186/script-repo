#!/bin/bash

# Prompt the user for the drive name
read -p "Enter the drive name (e.g., /dev/sda or /dev/nvme1n1): " DRIVE_NAME

# Prompt the user for the hostname
read -p "Enter the hostname for the system: " HOSTNAME

# Prompt the user for the root password
read -s -p "Enter the root password: " ROOT_PASSWORD
echo

# Prompt the user for the username
read -p "Enter the username for the new user account: " USERNAME

# Prompt the user for the user password
read -s -p "Enter the password for the user account: " USER_PASSWORD
echo

# Prompt the user for the timezone
read -p "Enter the timezone (e.g., America/New_York): " TIMEZONE

# Prompt the user for the system profile
read -p "Enter the system profile (e.g., default/linux/amd64/17.1): " SYSTEM_PROFILE

# Update the date and time
ntpd -q -g

# Partition the disk
parted -a optimal $DRIVE_NAME mklabel gpt
parted -a optimal $DRIVE_NAME mkpart primary 1 3
parted -a optimal $DRIVE_NAME name 1 grub
parted -a optimal $DRIVE_NAME set 1 bios_grub on
parted -a optimal $DRIVE_NAME mkpart primary 3 131
parted -a optimal $DRIVE_NAME name 2 boot
parted -a optimal $DRIVE_NAME mkpart primary 131 643
parted -a optimal $DRIVE_NAME name 3 swap
parted -a optimal $DRIVE_NAME mkpart primary 643 100%
parted -a optimal $DRIVE_NAME name 4 rootfs
parted -a optimal $DRIVE_NAME set 2 boot on

# Create and mount filesystems
mkfs.ext2 ${DRIVE_NAME}2
mkfs.ext4 ${DRIVE_NAME}4
mkswap ${DRIVE_NAME}3
swapon ${DRIVE_NAME}3
mount ${DRIVE_NAME}4 /mnt/gentoo

# Download and extract the stage3 tarball
cd /mnt/gentoo
wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64/stage3-amd64-*.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# Configure compile options
nano -w /mnt/gentoo/etc/portage/make.conf

# Copy DNS info
cp -L /etc/resolv.conf /mnt/gentoo/etc/

# Mount necessary filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

# Chroot into the new environment
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) ${PS1}"

# Sync the Portage tree
emerge-webrsync

# Configure the Portage options
nano -w /etc/portage/make.conf

# Select the system profile
eselect profile set $SYSTEM_PROFILE

# Update the @world set
emerge --ask --verbose --update --deep --newuse @world

# Configure the USE flags
nano -w /etc/portage/package.use/

# Install the necessary packages
emerge --ask app-portage/gentoolkit
emerge --ask sys-devel/gcc
emerge --ask sys-devel/binutils

# Configure the kernel
emerge --ask sys-kernel/gentoo-sources
cd /usr/src/linux
make menuconfig
make && make modules_install
make install
emerge --ask sys-kernel/genkernel
genkernel --install initramfs

# Install necessary system tools
emerge --ask sys-boot/grub:2
grub-install $DRIVE_NAME
grub-mkconfig -o /boot/grub/grub.cfg

# Set the root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create a user account
useradd -m -G users,wheel,audio,video -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configure the system
echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname
emerge --ask --noreplace net-misc/netifrc
nano -w /etc/conf.d/net

# Set the timezone
echo "$TIMEZONE" > /etc/timezone
emerge --config sys-libs/timezone-data

# Configure the fstab
nano -w /etc/fstab

# Configure the system logger
emerge --ask app-admin/sysklogd
rc-update add sysklogd default

# Configure the cron daemon
emerge --ask sys-process/cronie
rc-update add cronie default

# Install and configure the DHCP client
emerge --ask net-misc/dhcpcd
rc-update add dhcpcd default

# Install and configure the SSH server
emerge --ask net-misc/openssh
rc-update add sshd default

# Configure the network interface
nano -w /etc/conf.d/net

# Install and configure the system logger
emerge --ask app-admin/syslog-ng
rc-update add syslog-ng default

# Install and configure a bootloader
emerge --ask sys-boot/grub:2
grub-install $DRIVE_NAME
grub-mkconfig -o /boot/grub/grub.cfg

# Exit the chroot environment
exit

# Unmount the filesystems
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo

# Reboot the system
echo
read -p "Do you want to reboot? (y/n)" choice
case "$choice" in
    [yY]*) reboot ;;
    [nN]*|"") ;;
esac
