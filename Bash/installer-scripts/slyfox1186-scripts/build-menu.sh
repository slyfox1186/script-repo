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

# Clone or update one of the Python build projects, then run its launcher
python_builder() {
    local repo="$1" launcher="$2"
    shift 2
    if [[ -d "$repo/.git" ]]; then
        git -C "$repo" pull --ff-only || return 1
    else
        git clone "https://github.com/slyfox1186/$repo.git" || return 1
    fi
    (cd "$repo" && python3 "$launcher" "$@")
}

# Display the main menu
main_menu() {
    local options=(
        "7-Zip v24.06"
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
        2) download 'https://build-tools.optimizethis.net' ;;
        3) python_builder imagemagick-build-script build-magick.py --build ;;
        4) python_builder ffmpeg-build-script build-ffmpeg.py --build --latest ;;
        5) download 'https://gparted.optimizethis.net' ;;
        6) download 'https://players.optimizethis.net' ;;
        7) custom_user_scripts ;;
        8) extra_mirrors ;;
        9) download 'https://download.optimizethis.net' ;;
        10) exit 0 ;;
        *) echo "Invalid option. Please select a valid option." ;;
    esac
}

# Custom user scripts menu
custom_user_scripts() {
    local options=(
        "Ubuntu Jammy"
        "Exit"
    )

    for i in "${!options[@]}"; do
        echo "$((i+1))) ${options[i]}"
    done

    local choice
    read -p "Choose an option: " choice

    case $choice in
        1) download 'https://jammy-scripts.optimizethis.net' ;;
        2) exit 0 ;;
        *) echo "Invalid option. Please select a valid option." ;;
    esac
}

# Extra mirrors menu
extra_mirrors() {
    local options=(
        "Ubuntu Noble"
        "Ubuntu Jammy"
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
        1) download 'https://noble-mirrors.optimizethis.net' ;;
        2) download 'https://jammy.optimizethis.net' ;;
        3) download 'https://bookworm-mirrors.optimizethis.net' ;;
        4) download 'https://raspi-mirrors.optimizethis.net' ;;
        5) exit 0 ;;
        *) echo "Invalid option. Please select a valid option." ;;
    esac
}

# Start the main menu
main_menu
