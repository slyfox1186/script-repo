#!/bin/bash

# Interactive Gentoo (amd64, OpenRC) installer following the official handbook
# flow: partition -> stage3 -> chroot -> kernel -> bootloader.
# Run as root from a Gentoo live environment.

set -u

if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Prompt the user for the drive name
read -r -p "Enter the drive name (e.g., /dev/sda or /dev/nvme1n1): " DRIVE_NAME

if [[ ! -b "$DRIVE_NAME" ]]; then
    echo "Error: $DRIVE_NAME is not a block device." >&2
    exit 1
fi

# Prompt the user for the hostname
read -r -p "Enter the hostname for the system: " GENTOO_HOSTNAME

# Prompt the user for the root password
read -r -s -p "Enter the root password: " GENTOO_ROOT_PASSWORD
echo

# Prompt the user for the username
read -r -p "Enter the username for the new user account: " GENTOO_USERNAME

# Prompt the user for the user password
read -r -s -p "Enter the password for the user account: " GENTOO_USER_PASSWORD
echo

# Prompt the user for the timezone
read -r -p "Enter the timezone (e.g., America/New_York): " GENTOO_TIMEZONE

# Prompt the user for the system profile
read -r -p "Enter the system profile (e.g., default/linux/amd64/17.1): " GENTOO_PROFILE

# NVMe and MMC drives name partitions with a "p" separator (e.g., nvme1n1p2)
PART="$DRIVE_NAME"
[[ "$DRIVE_NAME" == *nvme* || "$DRIVE_NAME" == *mmcblk* ]] && PART="${DRIVE_NAME}p"

# Update the date and time
ntpd -q -g

# Partition the disk
parted -a optimal "$DRIVE_NAME" mklabel gpt
parted -a optimal "$DRIVE_NAME" mkpart primary 1 3
parted -a optimal "$DRIVE_NAME" name 1 grub
parted -a optimal "$DRIVE_NAME" set 1 bios_grub on
parted -a optimal "$DRIVE_NAME" mkpart primary 3 131
parted -a optimal "$DRIVE_NAME" name 2 boot
parted -a optimal "$DRIVE_NAME" mkpart primary 131 643
parted -a optimal "$DRIVE_NAME" name 3 swap
parted -a optimal "$DRIVE_NAME" mkpart primary 643 100%
parted -a optimal "$DRIVE_NAME" name 4 rootfs
parted -a optimal "$DRIVE_NAME" set 2 boot on

# Create and mount filesystems
mkfs.ext2 "${PART}2"
mkfs.ext4 "${PART}4"
mkswap "${PART}3"
swapon "${PART}3"
mkdir -p /mnt/gentoo
mount "${PART}4" /mnt/gentoo

# Download and extract the latest stage3 tarball (wget cannot glob URLs, so
# resolve the current filename from Gentoo's latest-stage3 manifest first)
cd /mnt/gentoo || exit 1
AUTOBUILDS_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds"
STAGE3_PATH=$(wget -qO- "$AUTOBUILDS_URL/latest-stage3-amd64-openrc.txt" | awk '/\.tar\.xz/{print $1; exit}')
if [[ -z "$STAGE3_PATH" ]]; then
    echo "Error: could not determine the latest stage3 tarball." >&2
    exit 1
fi
wget "$AUTOBUILDS_URL/$STAGE3_PATH" || exit 1
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner || exit 1

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

# Everything below must run INSIDE the new system, so write it to a script
# and execute it via chroot (a bare "chroot" would open an interactive shell
# and the remaining commands would run on the host after it exits)
cat > /mnt/gentoo/root/gentoo-stage2.sh <<'STAGE2'
#!/bin/bash

set -u

source /etc/profile
export PS1="(chroot) ${PS1:-}"

# Sync the Portage tree
emerge-webrsync

# Configure the Portage options
nano -w /etc/portage/make.conf

# Select the system profile
eselect profile set "$GENTOO_PROFILE"

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
cd /usr/src/linux || exit 1
make menuconfig
make && make modules_install
make install
emerge --ask sys-kernel/genkernel
genkernel --install initramfs

# Install and configure the bootloader
emerge --ask sys-boot/grub:2
grub-install "$DRIVE_NAME"
grub-mkconfig -o /boot/grub/grub.cfg

# Set the root password
echo "root:$GENTOO_ROOT_PASSWORD" | chpasswd

# Create a user account
useradd -m -G users,wheel,audio,video -s /bin/bash "$GENTOO_USERNAME"
echo "$GENTOO_USERNAME:$GENTOO_USER_PASSWORD" | chpasswd

# Configure the system
echo "hostname=\"$GENTOO_HOSTNAME\"" > /etc/conf.d/hostname
emerge --ask --noreplace net-misc/netifrc
nano -w /etc/conf.d/net

# Set the timezone
echo "$GENTOO_TIMEZONE" > /etc/timezone
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
STAGE2

chmod +x /mnt/gentoo/root/gentoo-stage2.sh

# Run the second stage inside the chroot; stdin/stdout stay attached to the
# terminal so the interactive steps (nano, emerge --ask) still work
DRIVE_NAME="$DRIVE_NAME" \
GENTOO_PROFILE="$GENTOO_PROFILE" \
GENTOO_HOSTNAME="$GENTOO_HOSTNAME" \
GENTOO_USERNAME="$GENTOO_USERNAME" \
GENTOO_TIMEZONE="$GENTOO_TIMEZONE" \
GENTOO_ROOT_PASSWORD="$GENTOO_ROOT_PASSWORD" \
GENTOO_USER_PASSWORD="$GENTOO_USER_PASSWORD" \
chroot /mnt/gentoo /bin/bash /root/gentoo-stage2.sh

rm -f /mnt/gentoo/root/gentoo-stage2.sh

# Unmount the filesystems
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo

# Reboot the system
echo
read -r -p "Do you want to reboot? (y/n) " choice
case "$choice" in
    [yY]*) reboot ;;
    [nN]*|"") ;;
esac
