#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
	local level color label
    level="${2:-info}"
    color="$GREEN"
    label="[LOG]"
    case "$level" in
        error)
            color="$RED"
            label="[ERROR]"
            ;;
        warning)
            color="$YELLOW"
            label="[WARN]"
            ;;
    esac
    echo -e "${color}${label}${NC} $1"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log "Run this script as root (or with sudo)." error
        exit 1
    fi
}

require_command() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "Missing required command: $cmd" error
            exit 1
        fi
    done
}

trim() {
	local value
    value=$1
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

prompt_variable() {
    local var_name prompt value 
    var_name="$1"
    prompt="$2"
    local -n target="$var_name"

    while true; do
        read -r -p "$prompt: " value
        value="$(trim "$value")"
        if [[ -z "$value" ]]; then
            log "This field is required." warning
            continue
        fi
        target="$value"
        break
    done
}

prompt_yes_no() {
    local prompt="$1"
    local answer
    while true; do
        read -r -p "$prompt (y/n): " answer
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

normalize_disk() {
    local disk="$1"
    if [[ "$disk" != /dev/* ]]; then
        disk="/dev/$disk"
    fi
    echo "$disk"
}

to_mib() {
    local input bytes
    input=$1
    bytes=$(numfmt --from=iec "$input")
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        log "Invalid size: $input" error
        exit 1
    fi
    echo $((bytes / 1024 / 1024))
}

size_plus_default() {
    local default trimmed value
    value=$1
    default=$2
    trimmed="$(trim "$value")"
    [[ -z "$trimmed" ]] && trimmed="$default"
    echo "$trimmed"
}

help() {
    cat <<EOF
Arch Linux GRUB installation helper

Usage: $0 [options]
  -u USERNAME       Set the non-root username
  -p USER_PASSWORD  Set the non-root user password
  -r ROOT_PASSWORD  Set the root password
  -c COMPUTER_NAME  Set the hostname
  -t TIMEZONE       Set timezone (default: US/Eastern)
  -d DISK           Set the target disk (for example: sda or nvme0n1)
  -h                Show this help

EOF
    exit 0
}

USERNAME=""
USER_PASSWORD=""
ROOT_PASSWORD=""
COMPUTER_NAME=""
TIMEZONE="US/Eastern"
DISK=""
KEYMAP_CHOICE="us"

PARTITION_COUNT=3
PARTITION1_SIZE="512M"
PARTITION2_SIZE="2G"
PARTITION_SIZES=()
PARTITION_TYPES=()

while getopts ":u:p:r:c:t:d:h" opt; do
    case "$opt" in
        u) USERNAME="$OPTARG" ;;
        p) USER_PASSWORD="$OPTARG" ;;
        r) ROOT_PASSWORD="$OPTARG" ;;
        c) COMPUTER_NAME="$OPTARG" ;;
        t) TIMEZONE="$OPTARG" ;;
        d) DISK="$OPTARG" ;;
        h) help ;;
        \?) log "Invalid option: -$OPTARG" error; exit 1 ;;
        :) log "Option -$OPTARG requires an argument." error; exit 1 ;;
    esac
done

shift "$((OPTIND - 1))"

setup_disk() {
    local part1_size part2_size input_count i part_end
    local efi_mib swap_mib part_num part_start

    read -r -p "EFI partition size (default: ${PARTITION1_SIZE}): " part1_size
    PARTITION1_SIZE="$(size_plus_default "$part1_size" "$PARTITION1_SIZE")"

    read -r -p "Swap partition size (default: ${PARTITION2_SIZE}): " part2_size
    PARTITION2_SIZE="$(size_plus_default "$part2_size" "$PARTITION2_SIZE")"

    while true; do
        read -r -p "Number of partitions (minimum 3, default 3): " input_count
        PARTITION_COUNT="$(size_plus_default "$input_count" "$PARTITION_COUNT")"
        if [[ "$PARTITION_COUNT" -ge 3 ]]; then
            break
        fi
        log "Minimum number of partitions is 3." warning
    done

    PARTITION_SIZES=()
    PARTITION_TYPES=()
    if (( PARTITION_COUNT > 3 )); then
        local size_input type_choice
        for ((i = 3; i < PARTITION_COUNT; i++)); do
            read -r -p "Enter size for partition $i (empty to use 1G): " size_input
            size_input="$(size_plus_default "$size_input" "1G")"
            PARTITION_SIZES+=("$size_input")
            echo "Partition type for partition $i"
            echo " 1) EFI System"
            echo " 2) BIOS Boot"
            echo " 4) BIOS Boot (compatibility)"
            echo "14) Linux root"
            echo "19) Linux swap"
            echo "23) Linux root (x86-64)"
            echo " 0) none"
            read -r -p "Select partition type [0]: " type_choice
            type_choice="$(trim "${type_choice:-0}")"
            PARTITION_TYPES+=("$type_choice")
        done
    fi

    echo
    log "About to wipe and partition ${FULL_DISK}"
    log "ALL DATA ON THIS DISK WILL BE DESTROYED" warning
    if ! prompt_yes_no "Are you sure this is the correct disk?"; then
        log "Aborted by user." error
        exit 1
    fi

    log "Partitioning ${FULL_DISK}..."
    parted -s "$FULL_DISK" mklabel gpt

    efi_mib="$(to_mib "$PARTITION1_SIZE")"
    swap_mib="$(to_mib "$PARTITION2_SIZE")"

    parted -s "$FULL_DISK" mkpart primary fat32 1MiB "${efi_mib}MiB"
    parted -s "$FULL_DISK" set 1 esp on
    parted -s "$FULL_DISK" mkpart primary linux-swap "${efi_mib}MiB" "$((efi_mib + swap_mib))MiB"
    parted -s "$FULL_DISK" set 2 swap on

    part_num=3
    part_start="$((efi_mib + swap_mib))"
    for ((i = 0; i < ${#PARTITION_SIZES[@]}; i++)); do
        local size_mib
        size_mib="$(to_mib "${PARTITION_SIZES[i]}")"
        part_end="$((part_start + size_mib))"
        parted -s "$FULL_DISK" mkpart primary "${part_start}MiB" "${part_end}MiB"

        case "${PARTITION_TYPES[i]}" in
            1) parted -s "$FULL_DISK" set "$part_num" esp on ;;
            2) parted -s "$FULL_DISK" set "$part_num" bios_grub on ;;
            4) parted -s "$FULL_DISK" set "$part_num" boot on ;;
            19|82|92|98) parted -s "$FULL_DISK" set "$part_num" swap on ;;
        esac
        part_start="$part_end"
        part_num=$((part_num + 1))
    done

    parted -s "$FULL_DISK" mkpart primary "${part_start}MiB" 100%
    PARTITION_COUNT="$part_num"
    DISK3="${FULL_DISK}${DISK_SUFFIX}${PARTITION_COUNT}"

    mkfs.fat -F 32 "$DISK1"
    mkswap "$DISK2"
    mkfs.ext4 "$DISK3"
}

mount_partitions() {
    swapon "$DISK2"
    mkdir -p /mnt
    mount "$DISK3" /mnt
    mkdir -p /mnt/boot/efi
    mount "$DISK1" /mnt/boot/efi
}

install_packages() {
    # FIX: grub-customizer removed — it is AUR-only and causes pacstrap to fail
    local base_packages=(
        base
        curl
        efibootmgr
        grub
        linux
        linux-firmware
        linux-headers
        nano
        networkmanager
        os-prober
        reflector
        sudo
        wget
    )
    local -a requested_packages=()
    local -A selected=()
    local pkg

    for pkg in "${base_packages[@]}"; do
        selected["$pkg"]=1
    done

    echo
    log "Current package set: ${base_packages[*]}"
    read -r -p "Add/remove packages (prefix remove with -). Example: xorg -nano: " package_input
    if [[ -n "${package_input}" ]]; then
        read -r -a requested_packages <<<"${package_input}"
        for pkg in "${requested_packages[@]}"; do
            if [[ "$pkg" == -* ]]; then
                pkg="${pkg#-}"
                unset "selected[$pkg]"
            else
                selected["$pkg"]=1
            fi
        done
    fi

    local -a final_packages=()
    for pkg in "${!selected[@]}"; do
        final_packages+=("$pkg")
    done
    mapfile -t final_packages < <(printf '%s\n' "${final_packages[@]}" | sort -u)

    pacstrap -K /mnt "${final_packages[@]}"
}

generate_fstab() {
    genfstab -U /mnt > /mnt/etc/fstab
}

configure_chroot() {
    log "Entering chroot to configure system."
    arch-chroot /mnt /usr/bin/env \
        USERNAME="$USERNAME" \
        USER_PASSWORD="$USER_PASSWORD" \
        ROOT_PASSWORD="$ROOT_PASSWORD" \
        TIMEZONE="$TIMEZONE" \
        COMPUTER_NAME="$COMPUTER_NAME" \
        KEYMAP="$KEYMAP_CHOICE" \
        /bin/bash -s <<'EOF'
set -euo pipefail

# Timezone
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# Locale
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# FIX: Create /etc/vconsole.conf — prevents mkinitcpio consolefont warning
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Hostname and hosts
echo "$COMPUTER_NAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${COMPUTER_NAME}.localdomain ${COMPUTER_NAME}
HOSTS

# FIX: Replace systemd-based initramfs hooks with busybox (udev) hooks.
# The default Arch mkinitcpio.conf now ships with systemd/sd-vconsole hooks
# which can cause the system to hang at "Loading initial ramdisk..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/' /etc/mkinitcpio.conf

# Build initramfs
mkinitcpio -P

# Users
useradd -m -G wheel -s /bin/bash "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd
printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd

# Sudo
install -d -m 750 /etc/sudoers.d
cat > /etc/sudoers.d/10-wheel <<'EOT'
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
EOT
chmod 0440 /etc/sudoers.d/10-wheel

# GRUB
# FIX: Use --bootloader-id=Arch to avoid conflicts with other distros
mkdir -p /boot/efi
grub-install --target=x86_64-efi --bootloader-id=Arch --efi-directory=/boot/efi

# FIX: Set nomodeset so system boots without GPU drivers installed.
# The post-reboot script removes nomodeset after installing NVIDIA drivers.
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 nomodeset"/' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg

# Fallback EFI entry
mkdir -p /boot/efi/EFI/BOOT
[[ -f /boot/efi/EFI/Arch/grubx64.efi ]] && cp -f /boot/efi/EFI/Arch/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

cat > /boot/efi/startup.nsh <<'EOF_NSH'
bcf boot add 1 fs0:\EFI\Arch\grubx64.efi "Arch Linux Bootloader"
exit
EOF_NSH

# Enable NetworkManager
systemctl enable NetworkManager
EOF
}

prompt_umount() {
    if prompt_yes_no "Installation complete. Unmount partitions now"; then
        umount -R /mnt
        swapoff -a
    fi
}

prompt_reboot() {
    if prompt_yes_no "Reboot now"; then
        reboot
    fi
}

main() {
    require_root
    require_command \
        chpasswd \
        loadkeys \
        localectl \
        mkfs.ext4 \
        mkfs.fat \
        mkswap \
        mount \
        numfmt \
        parted \
        pacstrap \
        swapon \
        systemctl \
        timedatectl \
        umount \
        useradd \
        genfstab \
        arch-chroot

    [[ -z "${USERNAME}" ]] && prompt_variable USERNAME "Enter the non-root username"
    while true; do
        if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            break
        fi
        log "Invalid username. Use only lowercase letters, digits, underscore and hyphen." error
        prompt_variable USERNAME "Enter the non-root username"
    done

    [[ -z "${USER_PASSWORD}" ]] && prompt_variable USER_PASSWORD "Enter the non-root user password"
    [[ -z "${ROOT_PASSWORD}" ]] && prompt_variable ROOT_PASSWORD "Enter the root password"
    [[ -z "${COMPUTER_NAME}" ]] && prompt_variable COMPUTER_NAME "Enter the computer name"
    [[ -z "${DISK}" ]] && prompt_variable DISK "Enter target disk (e.g., sda or nvme0n1)"

    FULL_DISK="$(normalize_disk "$DISK")"
    if [[ ! -b "$FULL_DISK" ]]; then
        log "Disk $FULL_DISK does not exist or is not a block device." error
        exit 1
    fi

    # Show disk info so user can verify it's the right one
    echo
    log "Selected disk:"
    lsblk -o NAME,SIZE,MODEL "$FULL_DISK"
    echo

    DISK_SUFFIX=""
    if [[ "$FULL_DISK" == /dev/nvme* || "$FULL_DISK" == /dev/mmcblk* ]]; then
        DISK_SUFFIX="p"
    fi

    DISK1="${FULL_DISK}${DISK_SUFFIX}1"
    DISK2="${FULL_DISK}${DISK_SUFFIX}2"
    DISK3="${FULL_DISK}${DISK_SUFFIX}3"

    read -r -p "Enter keyboard layout to load (press 'l' to list): " KEYMAP_CHOICE
    if [[ "$KEYMAP_CHOICE" == "l" || "$KEYMAP_CHOICE" == "L" ]]; then
        localectl list-keymaps | sed '/^#/d' || true
        read -r -p "Enter keyboard layout (or leave empty for 'us'): " KEYMAP_CHOICE
    fi
    if [[ -z "$KEYMAP_CHOICE" ]]; then
        KEYMAP_CHOICE="us"
    fi
    if ! loadkeys "$KEYMAP_CHOICE"; then
        log "Could not load keyboard layout '$KEYMAP_CHOICE'." warning
    fi

    log "Synchronizing system clock..."
    timedatectl set-ntp true

    log "Starting installation..."
    setup_disk
    mount_partitions
    install_packages
    generate_fstab
    configure_chroot
    prompt_umount
    prompt_reboot
}

main "$@"
