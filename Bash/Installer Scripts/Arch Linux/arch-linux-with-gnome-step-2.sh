
#!/usr/bin/env bash

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
    case $2 in
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

# Install required software using pacman
log "Installing required packages..." "info"
PACKAGES="gdm gedit gedit-plugins git gnome gnome-terminal gnome-text-editor gnome-tweaks nvidia pulseaudio pulseaudio-alsa reflector xorg xorg-server xorg-xinit"
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
    PACKAGES=$(echo "$PACKAGES" | sed "s/\b$pkg\b//g")
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

# Set vienv var
log "Setting vienvironment variable..." "info"
EDITOR=nano visudo

enable_nvidia_tweaks() {
    # Set Nvidia custom settings using tee
    echo "options nvidia_drm modeset=1" | tee "/etc/modprobe.d/nvidia-xorg-enable-drm.conf" >/dev/null

    # Enable Nvidia Driver update pacman hook using tee with a here-doc
    [[ ! -d "/etc/pacman.d/hooks/" ]] && mkdir -p "/etc/pacman.d/hooks/"
    tee "/etc/pacman.d/hooks/nvidia.hook" >/dev/null <<'EOF'
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
# Uncomment the installed NVIDIA package
Target=nvidia
#Target=nvidia-open
#Target=nvidia-lts
Target=linux
# Change the linux part above if a different kernel is used

[Action]
Description=Update NVIDIA module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case $trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'
EOF
}

echo
read -p "Do you want to enable Nvidia related tweaks? (y/n): " nvidia_choice
case "$nvidia_choice" in
    [yY]*) enable_nvidia_tweaks ;;
    [nN]*) ;;
esac

# Enable the LightDM display manager
echo
log "Enabling the GDM display manager..." "info"
echo
systemctl enable gdm.service
echo

prompt_gui() {
        read -p "Do you want to enter straight into the GUI? [not recommended] (y/n): " gui_choice
        case "$gui_choice" in
            [yY]*|[yY][eE][sS]*)
                systemctl start gdm.service
                exit 0
                ;;
            [nN]*|[nN][oO]*)
                ;;
            *)
                echo "Bad user input.. try again."
                sleep 3
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
                echo "Bad user input.. try again."
                sleep 3
                unset reboot_choice
                clear
                prompt_reboot
                ;;
        esac
    fi
}

prompt_gui
prompt_reboot
