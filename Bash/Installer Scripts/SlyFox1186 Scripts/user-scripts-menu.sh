#!/usr/bin/env bash
# Shellcheck disable=sc2001,sc2034,sc2162

# Create the color variables
GREEN="\033[0;32m"
YELLOW='\033[0;33m'
NC="\033[0m"

# Menu color functions
ColorGreen() {
    echo -ne "${GREEN}$1${NC}"
}

ColorBlue() {
    echo -ne "${YELLOW}$1${NC}"
}

# Show the script banner
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}
box_out_banner "User Scripts Installer"

# Display the main menu
main_menu() {
    local choice
echo -ne "
$(ColorGreen '1)') Ubuntu 24.04
$(ColorGreen '2)') Ubuntu (18/20/22).04
$(ColorGreen '3)') Debian 10/11/12
$(ColorGreen '4)') Arch Linux
$(ColorGreen '5)') Raspberry Pi
$(ColorGreen '0)') Exit
$(ColorBlue 'Choose your operating system:') "
    read -r choice
    clear

    case "$choice" in
        1) bash <(curl -fsSL "https://noble-scripts.optimizethis.net") ;;
        2) bash <(curl -fsSL "https://jammy-scripts.optimizethis.net") ;;
        3) bash <(curl -fsSL "https://bookworm-scripts.optimizethis.net") ;;
        4) bash <(curl -fsSL "https://arch-scripts.optimizethis.net") ;;
        5) bash <(curl -fsSL "https://raspi-scripts.optimizethis.net") ;;
        0) return 0 ;;
        *) unset choice
           clear
           main_menu
           ;;
    esac
}

main_menu
