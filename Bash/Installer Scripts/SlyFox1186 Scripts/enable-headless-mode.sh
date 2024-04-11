#!/usr/bin/env bash

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions
function log {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function warn {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

function fail {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if script is run as root
if [[ $EUID -eq 0 ]]; then
    fail "This script must not be run as root."
fi

log "This script will allow the user to quickly switch Ubuntu Desktop"
log "into its VGA or Headless Client mode as dictated by the startup"
log "commands located in /etc/default/grub."
echo

grub_config="/etc/default/grub"

if [[ ! -f $grub_config ]]; then
    fail "The main grub_config: $grub_config was not found."
fi

function display_menu {
    echo "[1] Headless Mode"
    echo "[2] VGA Mode"
    echo "[3] Exit"
    echo
    read -p "Your choices are (1 to 3): " choice
}

function update_grub {
    log "Updating grub..."
    if ! sudo update-grub; then
        fail "The update-grub command failed."
    fi
}

function enable_headless_mode {
    log "Enabling headless mode..."
    sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="3"/g' $grub_config
    update_grub
}

function enable_vga_mode {
    log "Enabling VGA mode..."
    sudo sed -i 's/GRUB_CMDLINE_LINUX="3"/GRUB_CMDLINE_LINUX=""/g' $grub_config
    update_grub
}

function prompt_reboot {
    echo
    read -p "Do you want to reboot the PC now? [y/N]: " reboot_choice
    case $reboot_choice in
        [Yy]*)
            log "Rebooting the PC..."
            sudo reboot
            ;;
        *)
            log "Skipping reboot."
            ;;
    esac
}

function main {
    while true; do
        display_menu
        case $choice in
            1)
                enable_headless_mode
                prompt_reboot
                break
                ;;
            2)
                enable_vga_mode
                prompt_reboot
                break
                ;;
            3)
                log "Exiting..."
                exit 0
                ;;
            *)
                warn "Input error: enter a number (1 to 3)"
                read -p "Press enter to start over or Ctrl+Z to exit: "
                ;;
        esac
    done
}

main
