#!/usr/bin/env bash

# Menu color functions
green='\e[32m'
blue='\e[34m'
clear='\e[0m'

ColorGreen() { echo -ne "${green}$1${clear}"; }
ColorBlue() { echo -ne "${blue}$1${clear}"; }

# Show script banner
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|'; echo -n "${space}"; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3; printf "%s\n" ' |';
    printf '|'; echo -n "${space}"; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner 'Installer Script Menu'

# Download scripts
download() {
    local url="$1"
    bash <(curl -fsSL "$url")
}

# Display the main menu
main_menu() {
    local options=(
        "7-Zip v24.06"
        "cURL, WGET, and Aria2c"
        "CMake, Meson, Ninja, and GoLang"
        "ImageMagick 7"
        "FFmpeg (Large script)"
        "GParted with libraries"
        "Video Players"
        "Custom User Scripts"
        "Extra Source Mirrors"
        "APT to Debian Package Downloader"
        "Exit"
    )

    for i in "${!options[@]}"; do
        echo "$((i+1))) ${options[i]}"
    done

    local choice
    read -p "Choose an option: " choice

    case $choice in
        1) download 'https://7z.optimizethis.net' ;;
        2) download 'https://dl-tools.optimizethis.net' ;;
        3) download 'https://build-tools.optimizethis.net' ;;
        4) download 'https://magick.optimizethis.net' ;;
        5) download 'https://build-ffmpeg.optimizethis.net' --build --latest ;;
        6) download 'https://gparted.optimizethis.net' ;;
        7) download 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/build-players' ;;
        8) custom_user_scripts ;;
        9) extra_mirrors ;;
        10) download 'https://download.optimizethis.net' ;;
        11) exit 0 ;;
        *) echo "Invalid option. Please select a valid option." ;;
    esac
}

# Custom user scripts menu
custom_user_scripts() {
    local options=(
        "Ubuntu Lunar"
        "Ubuntu Jammy, Focal, or Bionic"
        "Exit"
    )

    for i in "${!options[@]}"; do
        echo "$((i+1))) ${options[i]}"
    done

    local choice
    read -p "Choose an option: " choice

    case $choice in
        1) download 'https://lunar-scripts.optimizethis.net' ;;
        2) download 'https://jammy-scripts.optimizethis.net' ;;
        3) exit 0 ;;
        *) echo "Invalid option. Please select a valid option." ;;
    esac
}

# Extra mirrors menu
extra_mirrors() {
    local options=(
        "Ubuntu Lunar"
        "Ubuntu Jammy"
        "Ubuntu Focal"
        "Ubuntu Bionic"
        "Debian Bullseye"
        "Debian Bookworm"
        "Raspberry Pi (Based on Debian Bookworm)"
        "Exit"
    )

    for i in "${!options[@]}"; do
        echo "$((i+1))) ${options[i]}"
    done

    local choice
    read -p "Choose an option: " choice

    case $choice in
        1) download 'https://lunar-mirrors.optimizethis.net' ;;
        2) download 'https://jammy-mirrors.optimizethis.net' ;;
        3) download 'https://focal-mirrors.optimizethis.net' ;;
        4) download 'https://bionic-mirrors.optimizethis.net' ;;
        5) download 'https://bullseye-mirrors.optimizethis.net' ;;
        6) download 'https://bookworm-mirrors.optimizethis.net' ;;
        7) download 'https://raspi-scripts.optimizethis.net' ;;
        8) exit 0 ;;
        *) echo "Invalid option. Please select a valid option." ;;
    esac
}

# Start the main menu
main_menu
