#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure the script is not run as root
if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or with sudo."
    exit 1
fi

# Define color variables
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Create a temporary directory for storing files
temp_dir=$(mktemp -d)

execution_menu() {
    local url file
    url="$1"
    file="$2"

    # Download the chosen script
    if curl -LSso "$temp_dir/$file" "$url"; then
        if sudo bash "$temp_dir/$file"; then
            echo -e "${GREEN}[SUCCESS]${NC} Mirrors successfully installed."
        else
            echo -e "${RED}[ERROR]${NC} Failed to install the mirrors."
        fi
    else
        echo -e "${RED}[ERROR]${NC} Failed to download the script: \"$file\""
    fi

    # Remove the temp directory
    sudo rm -fr "$temp_dir"

    # Exit after executing the script
    exit 0
}

download_menu() {
    local choice os
    os="$1"

    # Handle Raspberry Pi directly
    if [[ "$os" == "raspi" ]]; then
        execution_menu "https://raspi-mirrors.optimizethis.net" "raspi-mirrors.sh"
        return 0
    fi

    # Handle Arch Linux directly
    if [[ "$os" == "arch" ]]; then
        if [[ ! -d "/etc/pacman.d" ]]; then
            sudo mkdir -p "/etc/pacman.d"
        fi
        execution_menu "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/Arch%20Linux/reflector-mirror-speed-test.sh" "reflector_mirror_test.sh"
        return 0
    fi

    case "$os" in
        ubuntu)
            echo -e "${GREEN}1)${NC} Ubuntu 24.04 - Noble Numbat"
            echo -e "${GREEN}2)${NC} Ubuntu 22.04 - Jammy Jellyfish"
            echo -e "${GREEN}3)${NC} Ubuntu 20.04 - Focal Fossa"
            echo -e "${GREEN}4)${NC} Ubuntu 18.04 - Bionic Beaver"
            ;;
        debian)
            echo -e "${GREEN}1)${NC} Debian 11 (Bullseye)"
            echo -e "${GREEN}2)${NC} Debian 12 (Bookworm)"
            ;;
    esac

    echo -e "${GREEN}0)${NC} Back"
    echo
    echo -en "${CYAN}Choose the $os release version: ${NC}"
    read -r choice
    clear

    case "$os:$choice" in
        ubuntu:1)
            execution_menu "https://noble-mirrors.optimizethis.net" "noble-mirrors.sh"
            ;;
        ubuntu:2)
            execution_menu "https://jammy.optimizethis.net" "jammy-mirrors.sh"
            ;;
        ubuntu:3)
            execution_menu "https://focal-mirrors.optimizethis.net" "focal-mirrors.sh"
            ;;
        ubuntu:4)
            execution_menu "https://bionic-mirrors.optimizethis.net" "bionic-mirrors.sh"
            ;;
        debian:1)
            execution_menu "https://bullseye-mirrors.optimizethis.net" "bullseye-mirrors.sh"
            ;;
        debian:2)
            execution_menu "https://bookworm-mirrors.optimizethis.net" "bookworm-mirrors.sh"
            ;;
        *)
            clear
            unset choice
            download_menu
            ;;
    esac
}

main_menu() {
    local choice
    while true; do
        echo -e "Linux Mirrors Script...\n"
        echo -e "${GREEN}1)${NC} Ubuntu"
        echo -e "${GREEN}2)${NC} Debian"
        echo -e "${GREEN}3)${NC} Raspberry Pi (Bookworm)"
        echo -e "${GREEN}4)${NC} Arch Linux"
        echo -e "${GREEN}0)${NC} Exit"
        echo
        echo -en "${CYAN}Choose an operating system: ${NC}"
        read -r choice
        clear
        case "$choice" in
            1)
                download_menu "ubuntu"
                ;;
            2)
                download_menu "debian"
                ;;
            3)
                download_menu "raspi"
                ;;
            4)
                download_menu "arch"
                ;;
            0)
                sudo rm -fr "$temp_dir"
                exit 0
                ;;
            *)
                clear
                unset choice
                main_menu
                ;;
        esac
    done
}

main_menu "$@"
