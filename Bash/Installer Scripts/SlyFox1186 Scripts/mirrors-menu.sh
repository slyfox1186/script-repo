#!/usr/bin/env bash

# Define color variables
GREEN='\e[0;32m'
CYAN='\e[0;36m'
MAGENTA='\e[0;35m'
RED='\033[0;31m'
NC='\e[0m' # No Color

# Create a temporary directory for storing files
dir=$(mktemp -d /tmp/mirrors-script-XXXXXX)

execute_arch() {
    local arch_flags="$1"
    if curl -Lso "$dir/$file" "$url"; then
        if [[ -f "$dir/$file" ]]; then
            if sudo bash "$dir/$file" $arch_flags; then
                sudo rm -rf "$dir"
                echo -e "${GREEN}[SUCCESS]${NC} Execution completed successfully.\n"
                exit 0
            else
                echo -e "${RED}[ERROR]${NC} Failed to execute: \"$file $flag\"\n"
                read -p "Press any key to exit."
                sudo rm -rf "$dir"
                exit 1
            fi
        else
            echo -e "${RED}[ERROR]${NC} File not found: \"$file\"\n"
            read -p "Press any key to exit."
            sudo rm -rf "$dir"
            exit 1
        fi
    else
        echo -e "${RED}[ERROR]${NC} Failed to download: \"$file\"\n"
        read -p "Press any key to exit."
        sudo rm -rf "$dir"
        exit 1
    fi
}

# Function to download and execute mirrors script
execute() {
    local url=$1
    local file=$2
    local flag=$3
    
    if [[ "$flag" == "arch" ]]; then
        flag_args="-m 30 -f daily -c US"
        execute_arch "$flag_args"
    fi

    if curl -Lso "$dir/$file" "$url"; then
        if [[ -f "$dir/$file" ]]; then
            if sudo bash "$dir/$file $flag"; then
                sudo rm -rf "$dir"
                echo -e "${GREEN}[SUCCESS]${NC} Execution completed successfully.\n"
                exit 0
            else
                echo -e "${RED}[ERROR]${NC} Failed to execute: \"$file $flag\"\n"
                read -p "Press any key to exit."
                sudo rm -rf "$dir"
                exit 1
            fi
        else
            echo -e "${RED}[ERROR]${NC} File not found: \"$file\"\n"
            read -p "Press any key to exit."
            sudo rm -rf "$dir"
            exit 1
        fi
    else
        echo -e "${RED}[ERROR]${NC} Failed to download: \"$file\"\n"
        read -p "Press any key to exit."
        sudo rm -rf "$dir"
        exit 1
    fi
}

# Function to display the ubuntu menu
ubuntu_menu() {
    local choice
    echo -e "${GREEN}1)${NC} Ubuntu 23.04 - Lunar Lobster"
    echo -e "${GREEN}2)${NC} Ubuntu 22.04 - Jammy Jellyfish"
    echo -e "${GREEN}3)${NC} Ubuntu 20.04 - Focal Fossa"
    echo -e "${GREEN}4)${NC} Ubuntu 18.04 - Bionic Beaver"
    echo -e "${GREEN}0)${NC} Back"
    echo
    echo -en "${CYAN}Choose the Ubuntu release version: ${NC}"
    read -n 1 choice
    clear
    case "$choice" in
        1) execute "https://lunar-mirrors.optimizethis.net" "lunar-mirrors.sh" ;;
        2) execute "https://jammy.optimizethis.net" "jammy-mirrors.sh" ;;
        3) execute "https://focal-mirrors.optimizethis.net" "focal-mirrors.sh" ;;
        4) execute "https://bionic-mirrors.optimizethis.net" "bionic-mirrors.sh" ;;
        0) clear ;;
        *) clear
           ubuntu_menu
           ;;
    esac
}

# Function to display the debian menu
debian_menu() {
    local choice
    echo -e "${GREEN}1)${NC} Debian 11 (Bullseye)"
    echo -e "${GREEN}2)${NC} Debian 12 (Bookworm)"
    echo -e "${GREEN}0)${NC} Back"
    echo
    echo -en "${CYAN}Choose the Debian release version: "
    read -n 1 choice
    clear
    case "$choice" in
        1) execute "https://bullseye-mirrors.optimizethis.net" "bullseye-mirrors.sh" ;;
        2) execute "https://bookworm-mirrors.optimizethis.net" "bookworm-mirrors.sh" ;;
        0) clear ;;
        *) clear
           debian_menu
           ;;
    esac
}

# Function to display the main menu
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
        read -n 1 choice
        clear
        case "$choice" in
            1) ubuntu_menu ;;
            2) debian_menu ;;
            3) execute "https://raspi-mirrors.optimizethis.net" "raspi-mirrors.sh" ;;
            4) sudo mkdir -p "/etc/pacman.d"
               execute "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Arch%20Linux%20Scripts/update_mirrorlist.sh" "update_mirrorlist.sh" "arch"
               ;;
            0) rm -rf "$dir"
               exit 0
               ;;
            *) clear
               main_menu
               ;;
        esac
    done
}

main_menu
