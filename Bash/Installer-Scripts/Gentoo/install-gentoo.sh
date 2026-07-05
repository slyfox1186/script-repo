#!/bin/bash
#
# Interactive Gentoo (amd64, OpenRC) installer following the official handbook
# flow: partition -> stage3 -> chroot -> kernel -> bootloader.
#
# Design notes (why this script looks the way it does):
#   * Firmware mode (UEFI vs legacy BIOS) is auto-detected from /sys/firmware/efi
#     and drives the whole disk/bootloader layout, so the produced system boots
#     on either firmware without the operator having to know in advance.
#   * The kernel is built from sys-kernel/gentoo-sources (source-based, the reason
#     most people run Gentoo) rather than a generic binary distribution kernel,
#     and userland is compiled with -march=native, so everything is tuned to the
#     exact CPU. sys-kernel/installkernel[dracut,grub] provides an automatic,
#     correct initramfs + grub.cfg so a hand-tuned kernel still boots reliably.
#   * The stage3 tarball is cryptographically verified against the Gentoo release
#     key before it is ever extracted.
#   * Everything that must run inside the new system is written to a script and
#     executed via chroot; a bare "chroot" would open an interactive shell and the
#     remaining commands would run on the host after it exits.
#
# Run as root from a Gentoo live environment with working networking.

set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || die "This script must be run as root."

# ---------------------------------------------------------------------------
# Detect firmware mode
# ---------------------------------------------------------------------------
if [[ -d /sys/firmware/efi ]]; then
    FIRMWARE="uefi"
else
    FIRMWARE="bios"
fi
echo "Detected firmware mode: ${FIRMWARE^^}"

# ---------------------------------------------------------------------------
# Gather and validate configuration
# ---------------------------------------------------------------------------
read -r -p "Enter the target drive (e.g. /dev/sda or /dev/nvme0n1): " DRIVE_NAME
[[ -b "$DRIVE_NAME" ]] || die "$DRIVE_NAME is not a block device."

read -r -p "Enter the hostname for the system: " GENTOO_HOSTNAME
[[ -n "$GENTOO_HOSTNAME" ]] || die "Hostname must not be empty."

read -r -p "Enter the username for the new user account: " GENTOO_USERNAME
[[ "$GENTOO_USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username '$GENTOO_USERNAME'."

read -r -p "Enter the timezone [UTC]: " GENTOO_TIMEZONE
GENTOO_TIMEZONE="${GENTOO_TIMEZONE:-UTC}"
[[ -f "/usr/share/zoneinfo/$GENTOO_TIMEZONE" ]] || die "Unknown timezone '$GENTOO_TIMEZONE'."

read -r -p "Enter the locale [en_US.UTF-8]: " GENTOO_LOCALE
GENTOO_LOCALE="${GENTOO_LOCALE:-en_US.UTF-8}"

read -r -p "Enter the system profile [default/linux/amd64/23.0]: " GENTOO_PROFILE
GENTOO_PROFILE="${GENTOO_PROFILE:-default/linux/amd64/23.0}"

# Passwords are read with confirmation and never echoed.
prompt_password() {
    # $1 = human label, $2 = name of the variable to populate
    local label="$1" varname="$2" first second
    while true; do
        read -r -s -p "Enter the $label password: " first; echo
        read -r -s -p "Confirm the $label password: " second; echo
        if [[ -n "$first" && "$first" == "$second" ]]; then
            printf -v "$varname" '%s' "$first"
            return 0
        fi
        echo "Passwords are empty or do not match; try again." >&2
    done
}
prompt_password "root account" GENTOO_ROOT_PASSWORD
prompt_password "user account" GENTOO_USER_PASSWORD

# ---------------------------------------------------------------------------
# Final destructive-action confirmation
# ---------------------------------------------------------------------------
echo
echo "About to ERASE ALL DATA on $DRIVE_NAME and install Gentoo (${FIRMWARE^^})."
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS "$DRIVE_NAME" 2>/dev/null || true
read -r -p "Type the drive path again to confirm: " CONFIRM
[[ "$CONFIRM" == "$DRIVE_NAME" ]] || die "Confirmation did not match; aborting."

# NVMe and MMC drives name partitions with a "p" separator (e.g. nvme0n1p2).
if [[ "$DRIVE_NAME" == *nvme* || "$DRIVE_NAME" == *mmcblk* ]]; then
    PART="${DRIVE_NAME}p"
else
    PART="$DRIVE_NAME"
fi
# Uniform partition numbering across both firmware modes:
#   p1 = ESP (UEFI) or BIOS-boot (legacy), p2 = swap, p3 = root
P1="${PART}1"
SWAP_PART="${PART}2"
ROOT_PART="${PART}3"

# ---------------------------------------------------------------------------
# Synchronise the clock (best effort; a wrong clock breaks TLS and GPG)
# ---------------------------------------------------------------------------
if command -v chronyd >/dev/null 2>&1; then
    chronyd -q 2>/dev/null || true
elif command -v ntpd >/dev/null 2>&1; then
    ntpd -q -g 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Partition the disk (GPT in both modes; parted --script is non-interactive)
# ---------------------------------------------------------------------------
# Swap sized from RAM: 2x for tiny machines, 1x mid-range, capped at 8 GiB.
mem_mib=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 ))
if   (( mem_mib <= 2048 )); then swap_mib=$(( mem_mib * 2 ))
elif (( mem_mib <= 8192 )); then swap_mib=$mem_mib
else                             swap_mib=8192
fi
(( swap_mib >= 2048 )) || swap_mib=2048

swapoff -a 2>/dev/null || true
wipefs -a "$DRIVE_NAME"
parted --script "$DRIVE_NAME" mklabel gpt

if [[ "$FIRMWARE" == "uefi" ]]; then
    # 1 GiB FAT32 EFI System Partition, then swap, then root.
    esp_end=$(( 1 + 1024 ))
    swap_end=$(( esp_end + swap_mib ))
    parted --script "$DRIVE_NAME" mkpart ESP fat32 1MiB "${esp_end}MiB"
    parted --script "$DRIVE_NAME" set 1 esp on
    parted --script "$DRIVE_NAME" mkpart swap linux-swap "${esp_end}MiB" "${swap_end}MiB"
    parted --script "$DRIVE_NAME" mkpart root ext4 "${swap_end}MiB" 100%
else
    # 2 MiB BIOS boot partition (holds GRUB core on GPT), then swap, then root.
    swap_end=$(( 3 + swap_mib ))
    parted --script "$DRIVE_NAME" mkpart BIOSboot 1MiB 3MiB
    parted --script "$DRIVE_NAME" set 1 bios_grub on
    parted --script "$DRIVE_NAME" mkpart swap linux-swap 3MiB "${swap_end}MiB"
    parted --script "$DRIVE_NAME" mkpart root ext4 "${swap_end}MiB" 100%
fi
partprobe "$DRIVE_NAME" 2>/dev/null || true
udevadm settle 2>/dev/null || true

# ---------------------------------------------------------------------------
# Create filesystems and mount the target root (+ ESP on UEFI)
# ---------------------------------------------------------------------------
if [[ "$FIRMWARE" == "uefi" ]]; then mkfs.vfat -F 32 "$P1"; fi
mkswap "$SWAP_PART"
swapon "$SWAP_PART"
mkfs.ext4 -F "$ROOT_PART"

mkdir -p /mnt/gentoo
mount "$ROOT_PART" /mnt/gentoo
if [[ "$FIRMWARE" == "uefi" ]]; then
    mkdir -p /mnt/gentoo/efi
    mount "$P1" /mnt/gentoo/efi
fi

# ---------------------------------------------------------------------------
# Download, verify and extract the latest stage3 tarball
# ---------------------------------------------------------------------------
# wget cannot glob URLs, so resolve the current filename from Gentoo's
# latest-stage3 manifest first.
cd /mnt/gentoo
AUTOBUILDS_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds"
STAGE3_PATH=$(wget -qO- "$AUTOBUILDS_URL/latest-stage3-amd64-openrc.txt" | awk '/\.tar\.xz/{print $1; exit}')
[[ -n "$STAGE3_PATH" ]] || die "Could not determine the latest stage3 tarball."
STAGE3_FILE=$(basename "$STAGE3_PATH")

wget -O "$STAGE3_FILE"     "$AUTOBUILDS_URL/$STAGE3_PATH"
wget -O "$STAGE3_FILE.asc" "$AUTOBUILDS_URL/$STAGE3_PATH.asc"

# Cryptographically verify the tarball against the Gentoo release key before
# extraction. Never install an unverified stage3.
command -v gpg >/dev/null 2>&1 || die "gpg is required to verify the stage3."
RELEASE_KEY="/usr/share/openpgp-keys/gentoo-release.asc"
[[ -f "$RELEASE_KEY" ]] || die "Gentoo release key not found at $RELEASE_KEY (run from official Gentoo media)."
GNUPGHOME=$(mktemp -d); export GNUPGHOME
gpg --batch --quiet --import "$RELEASE_KEY"
gpg --batch --verify "$STAGE3_FILE.asc" "$STAGE3_FILE" \
    || die "stage3 signature verification FAILED; refusing to continue."
echo "stage3 signature verified."

tar xpvf "$STAGE3_FILE" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
rm -f "$STAGE3_FILE" "$STAGE3_FILE.asc"

# ---------------------------------------------------------------------------
# Configure make.conf for this exact machine
# ---------------------------------------------------------------------------
MAKE_CONF="/mnt/gentoo/etc/portage/make.conf"
NPROC=$(nproc)
# -march=native tunes every compiled package to this CPU. COMMON_FLAGS must be
# set BEFORE the CFLAGS/CXXFLAGS lines that reference it, so edit in place.
sed -i 's|^COMMON_FLAGS=.*|COMMON_FLAGS="-O2 -pipe -march=native"|' "$MAKE_CONF"
if [[ "$FIRMWARE" == "uefi" ]]; then GRUB_PLATFORM="efi-64"; else GRUB_PLATFORM="pc"; fi
cat >> "$MAKE_CONF" <<EOF

# ---- added by install-gentoo.sh ----
MAKEOPTS="-j${NPROC}"
# Allow redistributable firmware/microcode blobs required for real hardware.
ACCEPT_LICENSE="@FREE @BINARY-REDISTRIBUTABLE"
GRUB_PLATFORMS="${GRUB_PLATFORM}"
EOF

echo
echo "Review /etc/portage/make.conf now (USE flags, VIDEO_CARDS, CPU_FLAGS_X86, etc.)."
read -r -p "Press Enter to open it in nano... "
nano -w "$MAKE_CONF"

# ---------------------------------------------------------------------------
# Prepare the chroot
# ---------------------------------------------------------------------------
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

# ---------------------------------------------------------------------------
# Generate /etc/fstab from the real partition UUIDs (deterministic, no editor)
# ---------------------------------------------------------------------------
root_uuid=$(blkid -s UUID -o value "$ROOT_PART")
swap_uuid=$(blkid -s UUID -o value "$SWAP_PART")
{
    echo "# /etc/fstab - generated by install-gentoo.sh"
    echo "UUID=${root_uuid}  /  ext4  defaults,noatime  0 1"
    echo "UUID=${swap_uuid}  none  swap  sw  0 0"
    if [[ "$FIRMWARE" == "uefi" ]]; then
        esp_uuid=$(blkid -s UUID -o value "$P1")
        echo "UUID=${esp_uuid}  /efi  vfat  defaults,noatime  0 2"
    fi
} > /mnt/gentoo/etc/fstab

# Pass credentials to the chroot via a root-only file (not the environment/argv,
# which are visible in `ps`). The stage-2 script shreds it after use.
umask 077
printf '%s\n%s\n' "$GENTOO_ROOT_PASSWORD" "$GENTOO_USER_PASSWORD" \
    > /mnt/gentoo/root/.install-credentials
chmod 600 /mnt/gentoo/root/.install-credentials

CPU_VENDOR=$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo)

# ---------------------------------------------------------------------------
# Stage 2: everything below runs INSIDE the new system.
# The heredoc is quoted ('STAGE2') so nothing is expanded here; runtime values
# arrive through the environment exported on the chroot command line below.
# ---------------------------------------------------------------------------
cat > /mnt/gentoo/root/gentoo-stage2.sh <<'STAGE2'
#!/bin/bash
set -euo pipefail

source /etc/profile
export PS1="(chroot) ${PS1:-}"

# All package installs go through this helper. --autounmask-continue makes Portage
# apply any USE-flag / keyword / license changes the dependency graph requires and
# then proceed, instead of aborting this unattended install with a "the following
# changes are necessary to proceed" message. Genuine blockers and hard-masked
# packages still stop the run, which is correct - those need a human decision.
emrg() { emerge --autounmask-continue "$@"; }

# Sync the Portage tree.
emerge-webrsync

# Select the system profile and apply it, then bring the base system in line.
eselect profile set "$GENTOO_PROFILE"
env-update && source /etc/profile

# Locale.
echo "$GENTOO_LOCALE UTF-8" >> /etc/locale.gen
locale-gen
cat > /etc/env.d/02locale <<EOF
LANG="$GENTOO_LOCALE"
LC_COLLATE="C.UTF-8"
EOF
env-update && source /etc/profile

# Timezone (modern symlink method).
ln -sf "../usr/share/zoneinfo/$GENTOO_TIMEZONE" /etc/localtime
echo "$GENTOO_TIMEZONE" > /etc/timezone

# Bring @world in line with the selected profile.
emrg --verbose --update --deep --newuse @world

# Firmware + CPU microcode so real hardware works.
emrg --noreplace sys-kernel/linux-firmware
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    emrg --noreplace sys-firmware/intel-microcode
fi

# installkernel drives initramfs (dracut) and bootloader config (grub) whenever a
# kernel is installed, so a hand-tuned kernel still ends up bootable.
mkdir -p /etc/portage/package.use
echo "sys-kernel/installkernel dracut grub" > /etc/portage/package.use/installkernel
emrg sys-kernel/installkernel

# GRUB must exist BEFORE the kernel's `make install`, because installkernel[grub]
# runs grub-mkconfig during installation.
emrg sys-boot/grub
if [[ "$FIRMWARE" == "uefi" ]]; then emrg sys-boot/efibootmgr; fi

# Kernel build prerequisites that a fresh stage3 does not ship.
emrg sys-devel/bc dev-libs/elfutils sys-libs/ncurses sys-devel/flex sys-devel/bison

# Kernel: source-based and tuned to this machine. defconfig gives a guaranteed
# bootable baseline; menuconfig lets the operator enable CONFIG_MNATIVE and trim
# drivers for the exact hardware. dracut (via installkernel) supplies the initramfs.
emrg sys-kernel/gentoo-sources
eselect kernel set 1
cd /usr/src/linux
make defconfig
# Drop BTF debug info to avoid a hard dependency on dev-util/dwarves (pahole).
scripts/config --disable DEBUG_INFO_BTF
make olddefconfig
echo
echo ">>> Opening menuconfig. For a CPU-tuned kernel enable:"
echo ">>>   Processor type and features -> Processor family -> Native optimizations"
echo ">>> and ensure your storage/filesystem drivers are built in or as modules."
echo ">>> Saving without changes still yields a bootable kernel."
read -r -p "Press Enter to continue... "
make menuconfig
make -j"$(nproc)"
make modules_install
make install

# Bootloader (grub/efibootmgr were installed above, before the kernel build).
if [[ "$FIRMWARE" == "uefi" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/efi
    # Also install to the firmware-agnostic fallback path so the system boots
    # even if an NVRAM boot entry cannot be created.
    grub-install --target=x86_64-efi --efi-directory=/efi --removable
else
    grub-install --target=i386-pc "$DRIVE_NAME"
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Accounts. Credentials come from the root-only file, which is then shredded.
{ read -r ROOT_PW; read -r USER_PW; } < /root/.install-credentials
echo "root:$ROOT_PW" | chpasswd
# Add only supplementary groups that actually exist, so useradd never aborts.
user_groups="users,wheel"
for g in audio video usb portage input; do
    if getent group "$g" >/dev/null 2>&1; then user_groups+=",$g"; fi
done
useradd -m -G "$user_groups" -s /bin/bash "$GENTOO_USERNAME"
echo "$GENTOO_USERNAME:$USER_PW" | chpasswd
shred -u /root/.install-credentials 2>/dev/null || rm -f /root/.install-credentials
unset ROOT_PW USER_PW

# Hostname (modern OpenRC location) and matching /etc/hosts entry.
echo "$GENTOO_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   $GENTOO_HOSTNAME.localdomain $GENTOO_HOSTNAME localhost
::1         $GENTOO_HOSTNAME.localdomain $GENTOO_HOSTNAME localhost
EOF

# Networking: a single DHCP client covers all interfaces (no netifrc conflict).
emrg net-misc/dhcpcd
rc-update add dhcpcd default

# System logger, cron and SSH.
emrg app-admin/sysklogd
rc-update add sysklogd default
emrg sys-process/cronie
rc-update add cronie default
emrg net-misc/openssh
rc-update add sshd default
STAGE2

chmod +x /mnt/gentoo/root/gentoo-stage2.sh

# Run stage 2 inside the chroot. stdin/stdout stay attached to the terminal so
# the interactive steps (nano, menuconfig) still work. Only non-secret values are
# passed through the environment; passwords travel via the root-only file above.
DRIVE_NAME="$DRIVE_NAME" \
FIRMWARE="$FIRMWARE" \
CPU_VENDOR="$CPU_VENDOR" \
GENTOO_PROFILE="$GENTOO_PROFILE" \
GENTOO_HOSTNAME="$GENTOO_HOSTNAME" \
GENTOO_USERNAME="$GENTOO_USERNAME" \
GENTOO_TIMEZONE="$GENTOO_TIMEZONE" \
GENTOO_LOCALE="$GENTOO_LOCALE" \
chroot /mnt/gentoo /bin/bash /root/gentoo-stage2.sh

rm -f /mnt/gentoo/root/gentoo-stage2.sh

# ---------------------------------------------------------------------------
# Tear down and offer to reboot
# ---------------------------------------------------------------------------
swapoff "$SWAP_PART" 2>/dev/null || true
umount -R /mnt/gentoo 2>/dev/null || umount -l -R /mnt/gentoo

echo
echo "Installation complete."
read -r -p "Reboot now? (y/N) " choice
case "$choice" in
    [yY]*) reboot ;;
    *)     echo "Not rebooting. Remove the install media before you do." ;;
esac
