#!/usr/bin/env bash

clear

echo -e "Starting Linux Mirrors Script...\n"

# Define Color functions
ColorGreen() { echo -ne "\e[32m${1}\e[0m"; }
ColorBlue() { echo -ne "\e[34m${1}\e[0m"; }

# Function to download and execute mirrors script
execute() {
    local url="$1"
    local output_file="$2"
    curl -Lso "$output_file" "$url"
    sudo bash "$output_file"
    if [ -f "$output_file" ]; then
        rm "$output_file"
    fi
}

# Function to display the main menu
main_menu() {
    echo -e "$(ColorGreen '1)') Ubuntu\n$(ColorGreen '2)') Debian\n$(ColorGreen '3)') Raspberry Pi (Bookworm)\n$(ColorGreen '4)') Arch Linux\n$(ColorGreen '5)') Exit"
    read -p "$(ColorBlue 'Choose an operating system: ')" answer
    echo -e "\nYou selected option $answer."
    clear
    case "${answer}" in
        1) 
            echo -e "$(ColorGreen '1)') Ubuntu 23.04 - Lunar Lobster\n$(ColorGreen '2)') Ubuntu 22.04 - Jammy Jellyfish\n$(ColorGreen '3)') Ubuntu 20.04 - Focal Fossa\n$(ColorGreen '4)') Ubuntu 18.04 - Bionic Beaver\n$(ColorGreen '0)') Back"
            read -p "$(ColorBlue 'Choose the Ubuntu release version: ')" answer
            echo -e "\nYou selected option $answer."
            clear
            case "${answer}" in
                1) execute 'https://lunar-mirrors.optimizethis.net' 'lunar-mirrors';;
                2) execute 'https://jammy.optimizethis.net' 'jammy-mirrors';;
                3) execute 'https://focal-mirrors.optimizethis.net' 'focal-mirrors';;
                4) execute 'https://bionic-mirrors.optimizethis.net' 'bionic-mirrors';;
                0) main_menu;;
                *) unset answer; clear; main_menu;;
            esac
            ;;
        2)
            echo -e "$(ColorGreen '1)') Debian 11 - Bullseye\n$(ColorGreen '2)') Debian 12 - Bookworm\n$(ColorGreen '3)') Back"
            read -p "$(ColorBlue 'Choose the Debian release version: ')" answer
            echo -e "\nYou selected option $answer."
            clear
            case "${answer}" in
                1) execute 'https://bullseye-mirrors.optimizethis.net' 'bullseye-mirrors';;
                2) execute 'https://bookworm-mirrors.optimizethis.net' 'bookworm-mirrors';;
                3) main_menu;;
                *) unset answer; clear; main_menu;;
            esac
            ;;
        3) execute 'https://raspi-mirrors.optimizethis.net' 'raspi-mirrors';;
        4)
            sudo mkdir -p /etc/pacman.d # Create the directory if it doesn't exist
            execute 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Arch%20Linux%20Scripts/archlinux-mirrors.sh' 'archlinux-mirrors'
            ;;
        5) return 0;;
        *) unset answer; clear; main_menu;;
    esac
    clear
}

# Initial call to the main menu
main_menu
