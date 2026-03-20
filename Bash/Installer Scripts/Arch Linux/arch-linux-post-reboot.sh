#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level="${2:-info}"
    local color="$GREEN"
    local label="[INFO]"
    if [[ "$level" == "warning" ]]; then
        color="$YELLOW"
        label="[WARNING]"
    fi
    echo -e "${color}${label}${NC} $1"
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log "This script must be run as root or with sudo." warning
        exit 1
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local answer
    while true; do
        read -r -p "$prompt (y/n): " answer
        case "${answer,,}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done
}

has_package() {
    local pkg="$1"
    pacman -Qq "$pkg" >/dev/null 2>&1
}

build_package_list() {
    local -a base_packages=("$@")
    local -a add_packages=() remove_packages=()
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

enable_nvidia_tweaks() {
    echo "options nvidia_drm modeset=1" > /etc/modprobe.d/nvidia-xorg-enable-drm.conf

    mkdir -p "/etc/pacman.d/hooks/"
    cat >/etc/pacman.d/hooks/nvidia.hook <<'EOF'
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia
#Target=nvidia-open
#Target=nvidia-lts
# If running a different kernel, modify below to match
Target=linux

[Action]
Description=Updating NVIDIA module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/usr/bin/sh -c 'while read -r trg; do case "$trg" in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'
EOF

    nvidia-xconfig
}

check_graphics_drivers() {
    local drivers=(
        xf86-video-intel
        xf86-video-amdgpu
        xf86-video-nouveau
        nvidia
        nvidia-open
        nvidia-open-dkms
        mesa
    )
    local driver installed=false
    for driver in "${drivers[@]}"; do
        if has_package "$driver"; then
            installed=true
            break
        fi
    done

    if ! $installed; then
        log "No graphics driver detected. Please install one before continuing." warning
        log "Common drivers: xf86-video-intel, xf86-video-amdgpu, xf86-video-nouveau, nvidia" warning
        read -r -p "Press Enter to continue..."
        echo
    fi
}

main() {
    require_root

    log "Detecting CPU microcode package..."
    CPU_VENDOR=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    case "$CPU_VENDOR" in
        GenuineIntel)
            MICROCODE_PACKAGE="intel-ucode"
            log "Intel CPU detected, adding intel microcode package."
            ;;
        AuthenticAMD)
            MICROCODE_PACKAGE="amd-ucode"
            log "AMD CPU detected, adding AMD microcode package."
            ;;
        *)
            MICROCODE_PACKAGE=""
            log "Unknown CPU vendor, proceeding without microcode package." warning
            ;;
    esac

    PACKAGES=(
        base-devel
        gdm
        gedit
        gedit-plugins
        git
        gnome
        gnome-terminal
        gnome-text-editor
        gnome-tweaks
        less
        nvidia
        os-prober
        pulseaudio
        pulseaudio-alsa
        reflector
        trash-cli
        xorg
        xorg-server
        xorg-xinit
    )

    if [[ -n "${MICROCODE_PACKAGE}" ]]; then
        PACKAGES+=("$MICROCODE_PACKAGE")
    fi

    build_package_list "${PACKAGES[@]}"
    pacman -Syu --needed --noconfirm "${BASE_FINAL_PACKAGES[@]}"

    check_graphics_drivers
    if prompt_yes_no "Do you want to enable Nvidia-related tweaks?"; then
        enable_nvidia_tweaks
    fi

    log "Enabling the GDM display manager..."
    systemctl enable gdm.service

    if prompt_yes_no "Do you want to enter the GUI now?"; then
        systemctl start gdm.service
        exit 0
    fi

    prompt_yes_no "Do you want to reboot now?" && reboot
}

main "$@"
