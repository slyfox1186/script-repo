#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level="${2:-info}"
    local color="$GREEN"
    local label="[LOG]"
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
        log "This script must be run as root or with sudo." error
        exit 1
    fi
}

prompt_yes_no() {
    local answer prompt
    prompt=$1

    while true; do
        read -r -p "$prompt (y/n): " answer
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

has_package() {
    local pkg
    pkg=$1
    pacman -Qq "$pkg" >/dev/null 2>&1
}

build_package_list() {
    local -a add_packages=() remove_packages=() base_packages=("$@")
    local raw_add raw_remove

    echo "The default packages set to be installed:"
    printf '  - %s\n' "${base_packages[@]}"
    echo

    read -r -p "Enter additional packages to install (space-separated) or press Enter to continue: " raw_add
    read -r -p "Enter packages to remove from the list (space-separated) or press Enter to continue: " raw_remove
    echo

    if [[ -n "$raw_add" ]]; then
        read -r -a add_packages <<< "$raw_add"
    fi
    if [[ -n "$raw_remove" ]]; then
        read -r -a remove_packages <<< "$raw_remove"
    fi

    local -A selected=()
    local pkg
    for pkg in "${base_packages[@]}"; do
        selected["$pkg"]=1
    done
    for pkg in "${add_packages[@]}"; do
        selected["$pkg"]=1
    done
    for pkg in "${remove_packages[@]}"; do
        unset "selected[$pkg]"
    done

    BASE_FINAL_PACKAGES=()
    for pkg in "${!selected[@]}"; do
        BASE_FINAL_PACKAGES+=("$pkg")
    done
    mapfile -t BASE_FINAL_PACKAGES < <(printf '%s\n' "${BASE_FINAL_PACKAGES[@]}" | sort -u)
}

detect_nvidia_package() {
    # FIX: The proprietary 'nvidia' package no longer exists in official repos.
    # Arch now provides nvidia-open as the standard driver for Turing+ GPUs (GTX 16xx, RTX 20xx+).
    # Fall back to nvidia-open-dkms if using a non-standard kernel.
    if pacman -Si nvidia-open &>/dev/null; then
        echo "nvidia-open"
    elif pacman -Si nvidia-open-dkms &>/dev/null; then
        echo "nvidia-open-dkms"
    else
        log "Could not find nvidia-open or nvidia-open-dkms in repos." warning
        log "You may need to install GPU drivers manually." warning
        echo
    fi
}

enable_nvidia_tweaks() {
    local nvidia_pkg="$1"

    # Enable DRM kernel modesetting for NVIDIA
    echo "options nvidia_drm modeset=1" > /etc/modprobe.d/nvidia-drm.conf

    # Pacman hook to rebuild initramfs when NVIDIA driver or kernel is updated
    mkdir -p /etc/pacman.d/hooks
    cat > /etc/pacman.d/hooks/nvidia.hook <<EOF
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=$nvidia_pkg
Target=linux

[Action]
Description=Rebuilding initramfs after NVIDIA driver update...
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/usr/bin/mkinitcpio -P
EOF

    log "NVIDIA tweaks applied (DRM modesetting + pacman hook)."
}

remove_nomodeset() {
    local grub_default
    grub_default=/etc/default/grub
    if grep -q 'nomodeset' "$grub_default"; then
        sed -i 's/ nomodeset//g' "$grub_default"
        grub-mkconfig -o /boot/grub/grub.cfg
        log "Removed nomodeset from GRUB config."
    else
        log "nomodeset was not present in GRUB config (already clean)."
    fi
}

main() {
    require_root

    # Detect CPU microcode
    log "Detecting CPU microcode package..."
    local cpu_vendor microcode_package
    cpu_vendor=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    case "$cpu_vendor" in
        GenuineIntel)
            microcode_package="intel-ucode"
            log "Intel CPU detected, adding intel-ucode."
            ;;
        AuthenticAMD)
            microcode_package="amd-ucode"
            log "AMD CPU detected, adding amd-ucode."
            ;;
        *)
            log "Unknown CPU vendor, skipping microcode package." warning
            ;;
    esac

    # Detect NVIDIA driver package name
    local nvidia_pkg
    nvidia_pkg="$(detect_nvidia_package)"
    [[ -n "$nvidia_pkg" ]] && log "NVIDIA driver package: $nvidia_pkg"

    # FIX: nvidia replaced with detected nvidia_pkg (nvidia-open),
    # pulseaudio replaced with pipewire (GNOME default on modern Arch)
    local -a packages=(
        base-devel
        gdm
        git
        gnome
        gnome-tweaks
        less
        nvidia-open
        nvidia-utils
        nvidia-settings
        os-prober
        pipewire
        pipewire-alsa
        pipewire-pulse
        wireplumber
        reflector
        trash-cli
        xorg-server
    )

    # Add detected packages
    [[ -n "$nvidia_pkg" ]] && packages+=("$nvidia_pkg")
    [[ -n "$microcode_package" ]] && packages+=("$microcode_package")

    build_package_list "${packages[@]}"

    log "Installing packages..."
    pacman -Syu --needed --noconfirm "${BASE_FINAL_PACKAGES[@]}"

    # NVIDIA tweaks
    if [[ -n "$nvidia_pkg" ]] && has_package "$nvidia_pkg"; then
        log "NVIDIA driver installed successfully."
        if prompt_yes_no "Apply NVIDIA tweaks (DRM modesetting + pacman hook)?"; then
            enable_nvidia_tweaks "$nvidia_pkg"
        fi
    else
        log "No NVIDIA driver was installed. You may need to install GPU drivers manually." warning
    fi

    # Remove nomodeset from GRUB since NVIDIA drivers are now installed
    log "Updating GRUB to remove nomodeset..."
    remove_nomodeset

    # Rebuild initramfs with NVIDIA modules
    log "Rebuilding initramfs..."
    mkinitcpio -P

    # Enable GDM
    log "Enabling the GDM display manager..."
    systemctl enable gdm.service

    echo
    log "Post-install complete!"
    log "On next boot, plug your HDMI into the NVIDIA card."
    echo

    if prompt_yes_no "Start the GNOME desktop now?"; then
        systemctl start gdm.service
        exit 0
    fi

    if prompt_yes_no "Reboot now?"; then
        reboot
    fi
}

main "$@"
