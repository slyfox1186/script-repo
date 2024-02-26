#!/usr/bin/env bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

fix_grub_errors() {
    # Check if /boot/grub directory exists, if not, create it
    if [ ! -d "/boot/grub" ]; then
        box_out_banner "Creating /boot/grub directory"
        if sudo mkdir -p /boot/grub; then
            echo "Error: Failed to create /boot/grub directory."
            exit 1
        fi
    fi

    # Generate GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    # Check if configuration generation was successful
    if [ $? -eq 0 ]; then
        echo "GRUB configuration has been successfully generated."
    else
        echo "Error: Generation of GRUB configuration failed."
    fi
}


# Function definitions for each task
update_system() {
    echo -e "${GREEN}Updating system packages...${NC}"
    if sudo pacman -Syu --noconfirm; then
        echo -e "${GREEN}[SUCCESS]${NC} System packages updated.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to update system packages.${NC}"
    fi
}

clean_package_cache() {
    echo -e "${GREEN}Cleaning package cache...${NC}"
    if sudo pacman -Sc --noconfirm; then
        echo -e "${GREEN}[SUCCESS]${NC} Package cache cleaned.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to clean the package cache.${NC}"
    fi
}

update_mirror_list() {
    echo -e "${GREEN}Updating mirror list...${NC}"
    if sudo reflector --latest 5 --sort rate --save /etc/pacman.d/mirrorlist; then
        echo -e "${GREEN}[SUCCESS]${NC} Mirror list updated.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to update the mirror list.${NC}"
    fi
}

update_aur_packages() {
    echo -e "${GREEN}Checking for yay AUR helper...${NC}"
    if ! command -v yay &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} yay AUR helper not found. Please install yay to update AUR packages.${NC}"
        echo -e "You can install yay by following these steps:"
        echo -e "${YELLOW}git clone https://aur.archlinux.org/yay.git${NC}"
        echo -e "${YELLOW}cd yay${NC}"
        echo -e "${YELLOW}makepkg -si${NC}"
        return 1
    fi
    echo -e "${GREEN}Updating AUR packages...${NC}"
    if yay -Syu --noconfirm; then
        echo -e "${GREEN}[SUCCESS]${NC} AUR packages updated.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to update the AUR packages.${NC}"
    fi
}

update_grub_configuration() {
    echo -e "${GREEN}Updating GRUB configuration...${NC}"
    if ! command -v grub-mkconfig &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} You must install the \"grub\" package to update GRUB.${NC}"
        echo -e "You can install grub by following these steps:"
        echo -e "${YELLOW}sudo pacman -Syu --noconfirm grub${NC}"
        return 1
    fi
    if sudo grub-mkconfig -o /boot/grub/grub.cfg; then
        echo -e "${GREEN}[SUCCESS]${NC} GRUB configuration updated.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to update the GRUB configuration.${NC}"
        echo "${YELLOW}[INFO]${NC} Attempting to fix the problem..."
        fix_grub_errors
    fi
}

check_and_apply_firmware_updates() {
    echo -e "${GREEN}Checking and applying firmware updates...${NC}"
    if ! command -v fwupdmgr &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} You must install the \"fwupd\" package to apply firmware updates.${NC}"
        echo -e "You can install fwupd by following these steps:"
        echo -e "${YELLOW}sudo pacman -Syu --noconfirm fwupd${NC}"
        return 1
    fi
    if sudo fwupdmgr get-updates && sudo fwupdmgr update; then
        echo -e "${GREEN}[SUCCESS]${NC} firmware updates applied.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to update the firmware.${NC}"
    fi
}

fix_pacman_keys() {
    echo -e "${YELLOW}Fixing pacman keys...${NC}"
    if sudo pacman-key --init && \
        sudo pacman-key --populate archlinux && \
        sudo pacman-key --refresh-keys
    then
        echo -e "${GREEN}[SUCCESS]${NC} Fixed pacman keys.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to update the firmware.${NC}"
    fi
}

check_filesystem() {
    echo -e "${YELLOW}Checking filesystem...${NC}"
    if sudo fsck -A; then
        echo -e "${GREEN}[SUCCESS]${NC} Checked the filesystem.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to check the filesystem.${NC}"
    fi
}

fix_network() {
    echo -e "${YELLOW}Fixing network issues...${NC}"
    if ! command -v fwupdmgr &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} You must install the \"networkmanager\" package to apply firmware updates.${NC}"
        echo -e "You can install networkmanager by following these steps:"
        echo -e "${YELLOW}sudo pacman -Sy${NC}"
        echo -e "${YELLOW}sudo pacman -Sy networkmanager --noconfirm${NC}"
        return 1
    fi
    if sudo systemctl restart NetworkManager; then
        echo -e "${GREEN}[SUCCESS]${NC} Fixed network issues.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to fix network issues.${NC}"
    fi
}

repair_grub_bootloader() {
    echo -e "${YELLOW}Repairing GRUB bootloader...${NC}"
    if sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB && \
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    then
        echo -e "${GREEN}[SUCCESS]${NC} Repaired the GRUB bootloader.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to fix network issues.${NC}"
    fi
}

check_hardware_issues() {
    if ! command -v lshw &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} You must install the \"lshw\" package to apply firmware updates.${NC}"
        echo -e "You can install lshw by following these steps:"
        echo -e "${YELLOW}sudo pacman -Sy${NC}"
        echo -e "${YELLOW}sudo pacman -Sy lshw --noconfirmy${NC}"
        return 1
    fi
    echo -e "${YELLOW}Checking for hardware issues...${NC}"
    if sudo lshw -short; then
        echo -e "${GREEN}[SUCCESS]${NC} Hardware check complete.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to check for hardware issues.${NC}"
    fi
}

restart_failed_systemd_services() {
    echo -e "${YELLOW}Restarting failed systemd services...${NC}"
    local failed_services=$(systemctl --failed --no-legend | awk '{print $1}')
    if for service in $failed_services; do
        echo "Restarting failed service: $service"
        sudo systemctl restart "$service"
    done
    then
        echo -e "${GREEN}[SUCCESS]${NC} Systemd services restarted.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to restart systemd.${NC}"
    fi
}

check_orphaned_packages() {
    echo -e "${RED}Checking for orphaned packages...${NC}"
    orphaned_packages=$(pacman -Qdtq)
    if [[ -z $orphaned_packages ]]; then
        echo "No orphaned packages found."
    else
        echo "Orphaned packages found:"
        echo $orphaned_packages
    fi
}

check_failed_systemd_services() {
    echo -e "${RED}Checking for failed systemd services...${NC}"
    if systemctl --failed; then
        echo -e "${GREEN}[SUCCESS]${NC} Systemd failed services check complete.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to check failed systemd services.${NC}"
    fi
}

system_health_report() {
    echo -e "${RED}Generating system health report...${NC}"
    echo "Disk Usage:"
    df -h
    echo "Memory Usage:"
    free -h
    echo "CPU Load:"
    uptime
}

check_disk_space() {
    echo -e "${RED}Checking disk space...${NC}"
    df -h
}

check_cpu_usage() {
    echo -e "${RED}Checking CPU usage...${NC}"
    top -n 1 | head -n 10
}

backup_important_directories() {
    echo -e "${GREEN}Backing up important directories...${NC}"
    if tar czvf "$HOME/backup-$(date +%Y-%m-%d).tar.gz" "$HOME/Documents" "$HOME/Pictures" "$HOME/Videos"; then
        echo -e "${GREEN}[SUCCESS]${NC} Systemd failed services check complete.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to check failed systemd services.${NC}"
    fi
}

enable_essential_services() {
    echo -e "${YELLOW}Enabling essential services...${NC}"
    if sudo systemctl enable NetworkManager && \
    sudo systemctl enable bluetooth
    then
        echo -e "${GREEN}[SUCCESS]${NC} Systemd services restarted.${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to restart systemd.${NC}"
    fi
}

# Interactive selection
prompt_user_selection() {
    echo -e "Select the operations you want to perform.\\n\\nEnter their numbers separated by commas, or specify a range using a dash.\\nFor example: 1,3,5-7\\n\\nGrouped by purpose:\\n"

    echo -e "${GREEN}System Updates and Maintenance:${NC}"
    echo "1. Update System"
    echo "2. Clean Package Cache"
    echo "3. Update Mirror List"
    echo "4. Update AUR Packages"
    echo "5. Update Grub Configuration"
    echo "6. Check and Apply Firmware Updates"

    echo -e "\\n${YELLOW}Troubleshooting and Repairs:${NC}"
    echo "7. Fix Pacman Keys"
    echo "8. Check Filesystem"
    echo "9. Fix Network"
    echo "10. Repair Grub Bootloader"
    echo "11. Check Hardware Issues"
    echo "12. Restart Failed Systemd Services"

    echo -e "\\n${RED}System Health and Reports:${NC}"
    echo "13. Check Orphaned Packages"
    echo "14. Check Failed Systemd Services"
    echo "15. System Health Report"
    echo "16. Check Disk Space"
    echo "17. Check CPU Usage"

    echo -e "\\n${GREEN}Backup and Recovery:${NC}"
    echo "18. Backup Important Directories"

    echo -e "\\n${PURPLE}Service Management:${NC}"
    echo -e "19. Enable Essential Services\\n"
    read -p "Your selection: " user_input
    echo

    # Parsing user input
    IFS=',' read -ra ADDR <<< "$user_input"
    for i in "${ADDR[@]}"; do
        if [[ $i == *-* ]]; then
            IFS='-' read -ra RANGE <<< "$i"
            for (( j=${RANGE[0]}; j<=${RANGE[1]}; j++ )); do
                run_operation $j
            done
        else
            run_operation $i
        fi
    done
}

run_operation() {
    case $1 in
        1) update_system ;;
        2) clean_package_cache ;;
        3) update_mirror_list ;;
        4) update_aur_packages ;;
        5) update_grub_configuration ;;
        6) check_and_apply_firmware_updates ;;
        7) fix_pacman_keys ;;
        8) check_filesystem ;;
        9) fix_network ;;
        10) repair_grub_bootloader ;;
        11) check_hardware_issues ;;
        12) restart_failed_systemd_services ;;
        13) check_orphaned_packages ;;
        14) check_failed_systemd_services ;;
        15) system_health_report ;;
        16) check_disk_space ;;
        17) check_cpu_usage ;;
        18) backup_important_directories ;;
        19) enable_essential_services ;;
    esac
}

prompt_user_selection
