#!/usr/bin/env bash
# shellcheck disable=SC2162

# Check if the script is being run with root privileges
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root or with sudo."
    exit 1
fi

# Color codes for logging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    case "$2" in
        "info")
            echo -e "${GREEN}[INFO]${NC} $1"
            ;;
        "warning")
            echo -e "${YELLOW}[WARNING]${NC} $1"
            ;;
        *)  echo "$1"
            ;;
    esac
}

# Detect CPU manufacturer and set microcode package
CPU_VENDOR=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
MICROCODE_PACKAGE=""

if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    MICROCODE_PACKAGE="intel-ucode"
    log "Intel CPU detected, adding Intel microcode package to installation..." "info"
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    MICROCODE_PACKAGE="amd-ucode"
    log "AMD CPU detected, adding AMD microcode package to installation..." "info"
else
    log "Unknown CPU vendor, proceeding without microcode package..." "warning"
fi

# Installation list of packages
PACKAGES="base-devel gdm gedit gedit-plugins git gnome gnome-terminal gnome-text-editor gnome-tweaks"
PACKAGES+=" less nvidia os-prober pulseaudio pulseaudio-alsa reflector trash-cli xorg xorg-server xorg-xinit"

# Append microcode package if detected
if [[ -n "$MICROCODE_PACKAGE" ]]; then
    PACKAGES+=" $MICROCODE_PACKAGE"
fi

printf "\n%s\n\n" "The default packages set to be installed: $PACKAGES"

# Prompt the user to add or remove packages
read -p "Enter additional packages to install (space-separated) or press Enter to continue: " ADDITIONAL_PACKAGES
read -p "Enter packages to remove from the list (space-separated) or press Enter to continue: " REMOVE_PACKAGES

# Add additional packages to the list
if [[ -n "$ADDITIONAL_PACKAGES" ]]; then
    PACKAGES="$PACKAGES $ADDITIONAL_PACKAGES"
fi

# Remove packages from the list
for pkg in $REMOVE_PACKAGES; do
    PACKAGES=$(echo "$PACKAGES" | sed "s/\b$(echo $pkg | sed 's/[.[\]*^$/]/\\&/g')\b//g")
done

# Install the packages
pacman -Sy --needed --noconfirm $PACKAGES

# Check if a graphics driver is installed
echo
log "Checking for installed graphics drivers..." "info"
echo

if ! pacman -Qs "xf86-video-" >/dev/null && ! pacman -Qs "nvidia" >/dev/null && ! pacman -Qs "mesa" >/dev/null; then
    log "No graphics driver detected. Please make sure to install a graphics driver for your system." "warning"
    log "Common drivers: xf86-video-intel, xf86-video-amdgpu, xf86-video-nouveau, nvidia" "warning"
    echo
    read -p "Press Enter to continue..."
    echo
fi

enable_nvidia_tweaks() {
    local nvidia_choice
    # Set Nvidia custom settings using tee
    echo "options nvidia_drm modeset=1" | tee "/etc/modprobe.d/nvidia-xorg-enable-drm.conf" >/dev/null

    # Enable Nvidia Driver update pacman hook using tee with a here-doc
    [[ ! -d "/etc/pacman.d/hooks/" ]] && mkdir -p "/etc/pacman.d/hooks/"
    tee em/etc/pacman.d/hooks/nvidia.hook >/dev/null <<'EOF'
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
# Uncomment the installed NVIDIA package
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
Exec=/bin/sh -c 'while read -r trg; do case $trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'
EOF

    echo "Creating the Xorg server configuration file"
    nvidia-xconfig
}

set_rendering_mode() {
    echo
    read -p "Are you running multiple graphics cards in SLI? (y/n): " nvidia_choice
    case "$nvidia_choice" in
        [yY]*|[yY][eE][sS]*)
            nvidia-xconfig --busid=PCI:3:0:0 --sli=AA
            ;;
        [nN]*|[nN][oO]*)
            nvidia-xconfig --busid=PCI:3:0:0 --sli=0
            ;;
        *)
            echo "Bas user input... Re-loading the question."
            sleep 4
            unset nvidia_choice
            clear
            set_rendering_mode
            ;;
    esac
}

echo
read -p "Do you want to enable Nvidia related tweaks? (y/n): " nvidia_choice
case "$nvidia_choice" in
    [yY]*|[yY][eE][sS]*)
        enable_nvidia_tweaks
        set_rendering_mode
        ;;
    [nN]*|[nN][oO]*)
        ;;
    *)  ;;
esac

# Enable the LightDM display manager
echo
log "Enabling the GDM display manager..." "info"
echo
systemctl enable gdm.service

prompt_gui() {
    echo
    read -p "Do you want to enter straight into the GUI? [not recommended] (y/n): " gui_choice
    case "$gui_choice" in
        [yY]*|[yY][eE][sS]*)
            systemctl start gdm.service
            exit 0
            ;;
        [nN]*|[nN][oO]*)
            ;;
        *)
            echo "Bad user input... try again."
            sleep 4
            unset gui_choice
            clear
            prompt_gui
            ;;
    esac
}

prompt_reboot() {
    read -p "Do you want to reboot now? [recommended] (y/n): " reboot_choice
    case "$reboot_choice" in
        [yY]*|[yY][eE][sS]*)
            reboot
            ;;
        [nN]*|[nN][oO]*)
            ;;
        *)
            echo "Bad user input... try again."
            sleep 4
            unset reboot_choice
            clear
            prompt_reboot
            ;;
    esac
}

prompt_gui
prompt_reboot
