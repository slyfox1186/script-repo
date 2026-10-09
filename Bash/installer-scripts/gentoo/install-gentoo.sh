#!/bin/bash
#
# Gentoo (amd64, OpenRC) installer - hands-off, source-based, hardware-tuned.
#
# Run as root from a Gentoo live environment with working networking. It asks a
# short set of questions up front, then installs unattended: no nano, no
# menuconfig, no mid-run prompts.
#
# What makes it more than a handbook transcription:
#   * Firmware (UEFI vs legacy BIOS) is auto-detected and drives the whole
#     disk + bootloader layout, so the result boots on either.
#   * The stage3 tarball is GPG-verified against the Gentoo release key before
#     it is ever extracted.
#   * Everything is compiled for THIS machine: -march=native userland, auto
#     CPU_FLAGS_X86 (cpuid2cpuflags), and a source kernel with native-CPU
#     optimisation. dracut (via installkernel) supplies a matching initramfs so
#     the tuned kernel still boots reliably.
#   * mirrorselect picks the fastest download mirrors.
#   * The whole run is logged, and it is RESUMABLE: if an emerge fails hours in,
#     re-run the script and choose resume - it skips the wipe and stage3 and
#     continues the idempotent in-chroot phase instead of starting over.
#   * A plan is shown before anything is erased, and a summary is printed at the
#     end. The wheel user gets working sudo.

set -euo pipefail

# --- logging -------------------------------------------------------------
LOG="/var/log/gentoo-install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p /var/log
# Mirror all output to the log while keeping it on screen. There are no
# full-screen TUIs in the default flow, so a piped stdout is safe.
exec > >(tee -a "$LOG") 2>&1

die() { echo "Error: $*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || die "This script must be run as root."

# --- firmware ------------------------------------------------------------
if [[ -d /sys/firmware/efi ]]; then FIRMWARE="uefi"; else FIRMWARE="bios"; fi
echo "Detected firmware mode: ${FIRMWARE^^}"

# --- gather + validate configuration ------------------------------------
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

# Passwords: confirmed, never echoed, never written to the log (read -s reads
# from the tty and does not emit to stdout).
prompt_password() {
    local label="$1" varname="$2" first second
    while true; do
        read -r -s -p "Enter the $label password: " first; echo
        read -r -s -p "Confirm the $label password: " second; echo
        if [[ -n "$first" && "$first" == "$second" ]]; then
            printf -v "$varname" '%s' "$first"; return 0
        fi
        echo "Passwords are empty or do not match; try again." >&2
    done
}
prompt_password "root account" GENTOO_ROOT_PASSWORD
prompt_password "user account" GENTOO_USER_PASSWORD

# --- derive partition names + swap size ---------------------------------
# NVMe and MMC drives name partitions with a "p" separator (e.g. nvme0n1p2).
if [[ "$DRIVE_NAME" == *nvme* || "$DRIVE_NAME" == *mmcblk* ]]; then
    PART="${DRIVE_NAME}p"
else
    PART="$DRIVE_NAME"
fi
# Uniform numbering in both modes: p1 = ESP (UEFI) or BIOS-boot (legacy),
# p2 = swap, p3 = root.
P1="${PART}1"; SWAP_PART="${PART}2"; ROOT_PART="${PART}3"

mem_mib=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 ))
if   (( mem_mib <= 2048 )); then swap_mib=$(( mem_mib * 2 ))
elif (( mem_mib <= 8192 )); then swap_mib=$mem_mib
else                             swap_mib=8192
fi
(( swap_mib >= 2048 )) || swap_mib=2048

# --- resume detection ----------------------------------------------------
RESUME=false
if blkid "$ROOT_PART" >/dev/null 2>&1; then
    probe=$(mktemp -d)
    if mount "$ROOT_PART" "$probe" 2>/dev/null; then
        [[ -f "$probe/etc/gentoo-release" ]] && found_gentoo=true || found_gentoo=false
        umount "$probe"
        if $found_gentoo; then
            echo
            echo "An existing Gentoo install was found on $ROOT_PART."
            read -r -p "Resume it (skip disk wipe + stage3)? [y/N]: " ans
            [[ "$ans" =~ ^[yY] ]] && RESUME=true
        fi
    fi
    rmdir "$probe"
fi

# --- plan preview + confirmation ----------------------------------------
echo
echo "==================== Installation plan ===================="
echo "  Firmware      : ${FIRMWARE^^}"
if $RESUME; then
    echo "  Mode          : RESUME (disk left intact, continue install)"
    echo "  Target        : $DRIVE_NAME"
else
    echo "  Mode          : FRESH INSTALL - ALL DATA ON $DRIVE_NAME IS ERASED"
    echo "  Disk (GPT)    :"
    if [[ "$FIRMWARE" == "uefi" ]]; then
        echo "     $P1  1 GiB          FAT32  EFI System -> /efi"
    else
        echo "     $P1  2 MiB          (BIOS boot, GRUB core)"
    fi
    echo "     $SWAP_PART  ${swap_mib} MiB  swap"
    echo "     $ROOT_PART  remaining     ext4   -> /"
fi
echo "  Hostname      : $GENTOO_HOSTNAME"
echo "  User          : $GENTOO_USERNAME (wheel + sudo)"
echo "  Timezone      : $GENTOO_TIMEZONE"
echo "  Locale        : $GENTOO_LOCALE"
echo "  Profile       : $GENTOO_PROFILE"
echo "  Optimisation  : -march=native, auto CPU_FLAGS_X86, native source kernel"
echo "  Log           : $LOG"
echo "==========================================================="
read -r -p "Type the drive path ($DRIVE_NAME) to confirm: " CONFIRM
[[ "$CONFIRM" == "$DRIVE_NAME" ]] || die "Confirmation did not match; aborting."

# --- clock ---------------------------------------------------------------
if command -v chronyd >/dev/null 2>&1; then chronyd -q 2>/dev/null || true
elif command -v ntpd >/dev/null 2>&1;   then ntpd -q -g 2>/dev/null || true; fi

# --- partition + format (skipped on resume) -----------------------------
if ! $RESUME; then
    swapoff -a 2>/dev/null || true
    wipefs -a "$DRIVE_NAME"
    parted --script "$DRIVE_NAME" mklabel gpt
    if [[ "$FIRMWARE" == "uefi" ]]; then
        esp_end=$(( 1 + 1024 )); swap_end=$(( esp_end + swap_mib ))
        parted --script "$DRIVE_NAME" mkpart ESP fat32 1MiB "${esp_end}MiB"
        parted --script "$DRIVE_NAME" set 1 esp on
        parted --script "$DRIVE_NAME" mkpart swap linux-swap "${esp_end}MiB" "${swap_end}MiB"
        parted --script "$DRIVE_NAME" mkpart root ext4 "${swap_end}MiB" 100%
    else
        swap_end=$(( 3 + swap_mib ))
        parted --script "$DRIVE_NAME" mkpart BIOSboot 1MiB 3MiB
        parted --script "$DRIVE_NAME" set 1 bios_grub on
        parted --script "$DRIVE_NAME" mkpart swap linux-swap 3MiB "${swap_end}MiB"
        parted --script "$DRIVE_NAME" mkpart root ext4 "${swap_end}MiB" 100%
    fi
    partprobe "$DRIVE_NAME" 2>/dev/null || true
    udevadm settle 2>/dev/null || true

    if [[ "$FIRMWARE" == "uefi" ]]; then mkfs.vfat -F 32 "$P1"; fi
    mkswap "$SWAP_PART"
    mkfs.ext4 -F "$ROOT_PART"
fi
swapon "$SWAP_PART" 2>/dev/null || true

# --- mount target (idempotent) ------------------------------------------
domount() { local tgt="${!#}"; mountpoint -q "$tgt" || mount "$@"; }
mkdir -p /mnt/gentoo
domount "$ROOT_PART" /mnt/gentoo
if [[ "$FIRMWARE" == "uefi" ]]; then
    mkdir -p /mnt/gentoo/efi
    domount "$P1" /mnt/gentoo/efi
fi

# --- stage3: download, verify, extract (skipped on resume) --------------
if ! $RESUME; then
    cd /mnt/gentoo
    AUTOBUILDS_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds"
    STAGE3_PATH=$(wget -qO- "$AUTOBUILDS_URL/latest-stage3-amd64-openrc.txt" | awk '/\.tar\.xz/{print $1; exit}')
    [[ -n "$STAGE3_PATH" ]] || die "Could not determine the latest stage3 tarball."
    STAGE3_FILE=$(basename "$STAGE3_PATH")
    wget -O "$STAGE3_FILE"     "$AUTOBUILDS_URL/$STAGE3_PATH"
    wget -O "$STAGE3_FILE.asc" "$AUTOBUILDS_URL/$STAGE3_PATH.asc"

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
fi

# --- make.conf: tune for this exact machine (idempotent) ----------------
MAKE_CONF="/mnt/gentoo/etc/portage/make.conf"
if ! grep -q "install-gentoo.sh" "$MAKE_CONF" 2>/dev/null; then
    NPROC=$(nproc)
    # COMMON_FLAGS must be set BEFORE the CFLAGS/CXXFLAGS lines that reference it.
    sed -i 's|^COMMON_FLAGS=.*|COMMON_FLAGS="-O2 -pipe -march=native"|' "$MAKE_CONF"
    if [[ "$FIRMWARE" == "uefi" ]]; then GRUB_PLATFORM="efi-64"; else GRUB_PLATFORM="pc"; fi
    cat >> "$MAKE_CONF" <<EOF

# ---- added by install-gentoo.sh ----
# Load-limited parallel make: uses all cores but backs off under load, avoiding
# the nproc*nproc thread blow-up (and OOM) of also parallelising emerge itself.
MAKEOPTS="-j${NPROC} -l${NPROC}"
# Allow redistributable firmware/microcode blobs required for real hardware.
ACCEPT_LICENSE="@FREE @BINARY-REDISTRIBUTABLE"
GRUB_PLATFORMS="${GRUB_PLATFORM}"
EOF
fi

# --- prepare chroot ------------------------------------------------------
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
domount --types proc /proc /mnt/gentoo/proc
domount --rbind /sys /mnt/gentoo/sys;  mount --make-rslave /mnt/gentoo/sys
domount --rbind /dev /mnt/gentoo/dev;  mount --make-rslave /mnt/gentoo/dev
domount --bind /run /mnt/gentoo/run;   mount --make-slave  /mnt/gentoo/run

# fstab from real UUIDs (deterministic; regenerating on resume is harmless).
root_uuid=$(blkid -s UUID -o value "$ROOT_PART")
swap_uuid=$(blkid -s UUID -o value "$SWAP_PART")
{
    echo "# /etc/fstab - generated by install-gentoo.sh"
    echo "UUID=${root_uuid}  /  ext4  defaults,noatime  0 1"
    echo "UUID=${swap_uuid}  none  swap  sw  0 0"
    if [[ "$FIRMWARE" == "uefi" ]]; then
        echo "UUID=$(blkid -s UUID -o value "$P1")  /efi  vfat  defaults,noatime  0 2"
    fi
} > /mnt/gentoo/etc/fstab

# Credentials travel via a root-only file, not argv/env (which show up in ps).
umask 077
printf '%s\n%s\n' "$GENTOO_ROOT_PASSWORD" "$GENTOO_USER_PASSWORD" \
    > /mnt/gentoo/root/.install-credentials
chmod 600 /mnt/gentoo/root/.install-credentials

CPU_VENDOR=$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo)

# --- stage 2: runs INSIDE the new system --------------------------------
# Quoted heredoc: nothing is expanded here; runtime values arrive via the
# environment exported on the chroot line below. Every step is idempotent so a
# resumed run continues cleanly from wherever a previous run stopped.
cat > /mnt/gentoo/root/gentoo-stage2.sh <<'STAGE2'
#!/bin/bash
set -euo pipefail
source /etc/profile
export PS1="(chroot) ${PS1:-}"

# --autounmask-continue makes Portage apply required USE/keyword/license changes
# and proceed instead of aborting an unattended install; real blockers still stop.
emrg() { emerge --autounmask-continue "$@"; }

# Portage tree.
emerge-webrsync

# Fastest mirrors (idempotent: only if not already chosen).
emrg app-portage/mirrorselect
if ! grep -q '^GENTOO_MIRRORS=' /etc/portage/make.conf; then
    mirrorselect -s5 -o >> /etc/portage/make.conf || echo "mirrorselect failed; keeping default mirrors"
fi

# Exact per-CPU instruction sets for every package build.
emrg app-portage/cpuid2cpuflags
mkdir -p /etc/portage/package.use
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags

# Profile.
eselect profile set "$GENTOO_PROFILE"
env-update && source /etc/profile

# Locale (idempotent).
grep -qxF "$GENTOO_LOCALE UTF-8" /etc/locale.gen || echo "$GENTOO_LOCALE UTF-8" >> /etc/locale.gen
locale-gen
cat > /etc/env.d/02locale <<EOF
LANG="$GENTOO_LOCALE"
LC_COLLATE="C.UTF-8"
EOF
env-update && source /etc/profile

# Timezone (modern symlink method).
ln -sf "../usr/share/zoneinfo/$GENTOO_TIMEZONE" /etc/localtime
echo "$GENTOO_TIMEZONE" > /etc/timezone

# Bring @world in line with the profile and CPU flags.
emrg --verbose --update --deep --newuse @world

# Firmware + CPU microcode so real hardware works.
emrg --noreplace sys-kernel/linux-firmware
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then emrg --noreplace sys-firmware/intel-microcode; fi

# installkernel[dracut,grub]: automatic initramfs + grub.cfg on every kernel
# install. GRUB must exist before the kernel's `make install` calls grub-mkconfig.
echo "sys-kernel/installkernel dracut grub" > /etc/portage/package.use/installkernel
emrg sys-kernel/installkernel
emrg sys-boot/grub
if [[ "$FIRMWARE" == "uefi" ]]; then emrg sys-boot/efibootmgr; fi

# Kernel build prerequisites a fresh stage3 does not ship.
emrg sys-devel/bc dev-libs/elfutils sys-devel/flex sys-devel/bison

# Source kernel, tuned to this CPU, no interactive config. defconfig is a
# guaranteed-bootable baseline; native optimisation is enabled programmatically;
# dracut supplies the initramfs so module-based drivers still find root.
emrg sys-kernel/gentoo-sources
eselect kernel set 1
# Skip the (multi-hour) rebuild if a resumed run already installed a kernel.
if ! ls /boot/vmlinuz-* >/dev/null 2>&1; then
    cd /usr/src/linux
    make defconfig
    scripts/config --disable DEBUG_INFO_BTF
    # Enable native-CPU optimisation under whatever symbol this kernel version uses.
    for sym in MNATIVE MNATIVE_INTEL MNATIVE_AMD X86_NATIVE_CPU; do
        scripts/config --enable "$sym" 2>/dev/null || true
    done
    make olddefconfig
    make -j"$(nproc)"
    make modules_install
    make install
fi

# Bootloader core (grub/efibootmgr already installed above).
if [[ "$FIRMWARE" == "uefi" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/efi
    # Fallback path so it boots even without an NVRAM entry.
    grub-install --target=x86_64-efi --efi-directory=/efi --removable
else
    grub-install --target=i386-pc "$DRIVE_NAME"
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Accounts (idempotent). Credentials come from the root-only file, then shredded.
{ read -r ROOT_PW; read -r USER_PW; } < /root/.install-credentials
echo "root:$ROOT_PW" | chpasswd
if ! id "$GENTOO_USERNAME" >/dev/null 2>&1; then
    groups="users,wheel"
    for g in audio video usb portage input; do
        if getent group "$g" >/dev/null 2>&1; then groups+=",$g"; fi
    done
    useradd -m -G "$groups" -s /bin/bash "$GENTOO_USERNAME"
fi
echo "$GENTOO_USERNAME:$USER_PW" | chpasswd
shred -u /root/.install-credentials 2>/dev/null || rm -f /root/.install-credentials
unset ROOT_PW USER_PW

# sudo for the wheel group so the new user can actually administer the box.
emrg app-admin/sudo
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# Hostname (modern OpenRC location) + matching /etc/hosts.
echo "$GENTOO_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   $GENTOO_HOSTNAME.localdomain $GENTOO_HOSTNAME localhost
::1         $GENTOO_HOSTNAME.localdomain $GENTOO_HOSTNAME localhost
EOF

# Networking: one DHCP client covers all interfaces (no netifrc conflict).
emrg net-misc/dhcpcd
rc-update add dhcpcd default

# Handy Portage tooling, logger, cron, SSH.
emrg app-portage/gentoolkit
emrg app-admin/sysklogd; rc-update add sysklogd default
emrg sys-process/cronie; rc-update add cronie default
emrg net-misc/openssh;   rc-update add sshd default
STAGE2

chmod +x /mnt/gentoo/root/gentoo-stage2.sh

# Run stage 2. stdin/stdout stay attached so progress is visible and logged.
# Only non-secret values go through the environment.
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

# --- summary + teardown --------------------------------------------------
installed_kernel="unknown"
for k in /mnt/gentoo/boot/vmlinuz-*; do
    if [[ -e "$k" ]]; then installed_kernel=$(basename "$k"); fi
done
cp -f "$LOG" /mnt/gentoo/var/log/ 2>/dev/null || true

sync
swapoff "$SWAP_PART" 2>/dev/null || true
umount -R /mnt/gentoo 2>/dev/null || umount -l -R /mnt/gentoo

echo
echo "==================== Install complete ===================="
echo "  System        : Gentoo ${FIRMWARE^^}, profile $GENTOO_PROFILE"
echo "  Kernel        : $installed_kernel (source, -march=native)"
echo "  Disk          : $DRIVE_NAME"
echo "  Bootloader    : GRUB ($([[ $FIRMWARE == uefi ]] && echo 'UEFI /efi' || echo 'BIOS'))"
echo "  User          : $GENTOO_USERNAME (sudo via wheel)"
echo "  Full log      : $LOG (also copied to /var/log on the new system)"
echo "=========================================================="
read -r -p "Reboot now? (y/N) " choice
case "$choice" in
    [yY]*) reboot ;;
    *)     echo "Not rebooting. Remove the install media before you do." ;;
esac
