#!/usr/bin/env bash
#shellcheck disable=SC2000,SC2034,2086,SC2162

clear

user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

#
# MENU COLOR FUNCTIONS
#

green='\e[32m'
blue='\e[34m'
clear='\e[0m'
ColorGreen() { echo -ne "${green}${1}${clear}"; }
ColorBlue() { echo -ne "${blue}${1}${clear}"; }

#
# SHOW SCRIPT BANNER
#

box_out_banner() {
    input_char=$(echo "${@}" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)${line}"
    space=${line//-/ }
    echo " ${line}"
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "${@}"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    echo " ${line}"
    tput sgr 0
}
box_out_banner 'Linux Mirrors Script'

#
# DETERMINE WHAT DOWNLOADER TO USE
#

if ! sudo dpkg -l | grep -o curl &>/dev/null; then
    sudo apt update
    sudo apt -y install curl
    clear
fi

#
# DISPLAY DEBIAN MIRRORS MENU
#

debian_mirrors_fn() {
    local answer
echo -ne "
$(ColorGreen '1)') Debian 11 - Bullseye
$(ColorGreen '2)') Debian 12 - Bookworm
$(ColorGreen '3)') Back
$(ColorBlue 'Choose the Debian release version:') "
    read answer
    clear
    case "${answer}" in
        1)
                curl -A "$user_agent" -Lso 'bullseye-mirrors' 'https://bullseye-mirrors.optimizethis.net'
                sudo bash 'bullseye-mirrors'
                rm 'bullseye-mirrors'
                return 0
                ;;
        2)
                curl -A "$user_agent" -Lso 'bookworm-mirrors' 'https://bookworm-mirrors.optimizethis.net'
                sudo bash 'bookworm-mirrors'
                rm 'bookworm-mirrors'
                return 0
                ;;
        3)      main_menu;;
        *)
                unset answer
                clear
                debian_mirrors_fn
                ;;
    esac
    clear
}
clear

#
# DISPLAY UBUNTU MIRRORS MENU
#

ubuntu_mirrors_fn() {
    local answer
echo -ne "
$(ColorGreen '1)') Ubuntu 23.04 - Lunar Lobster
$(ColorGreen '2)') Ubuntu 22.04 - Jammy Jellyfish
$(ColorGreen '3)') Ubuntu 20.04 - Focal Fossa
$(ColorGreen '4)') Ubuntu 18.04 - Bionic Beaver
$(ColorGreen '0)') Back
$(ColorBlue 'Choose the Ubuntu release version:') "
    read answer
    clear
    case "${answer}" in
        1)
                curl -A "$user_agent" -Lso 'lunar-mirrors' 'https://lunar-mirrors.optimizethis.net'
                sudo bash 'lunar-mirrors'
                rm 'lunar-mirrors'
                return 0
                ;;
        2)
                curl -A "$user_agent" -Lso 'jammy-mirrors' 'https://jammy.optimizethis.net'
                sudo bash 'jammy-mirrors'
                rm 'jammy-mirrors'
                return 0
                ;;
        3)
                curl -A "$user_agent" -Lso 'focal-mirrors' 'https://focal-mirrors.optimizethis.net'
                sudo bash 'focal-mirrors'
                rm 'focal-mirrors'
                return 0
                ;;
        4)
                curl -A "$user_agent" -Lso 'bionic-mirrors' 'https://bionic-mirrors.optimizethis.net'
                sudo bash 'bionic-mirrors'
                rm 'bionic-mirrors'
                return 0
                ;;
        0)      main_menu;;
        *)
                unset answer
                clear
                ubuntu_mirrors_fn
                ;;
    esac
    clear
}

#
# DISPLAY THE MAIN MENU
#

main_menu() {
    local answer
echo -ne "
$(ColorGreen '1)') Ubuntu
$(ColorGreen '2)') Debian
$(ColorGreen '3)') Raspberry Pi (Bookworm)
$(ColorGreen '4)') Arch Linux
$(ColorGreen '5)') Exit
$(ColorBlue 'Choose an operating system:') "
    read answer
    clear
    case "${answer}" in
        1)      ubuntu_mirrors_fn;;
        2)      debian_mirrors_fn;;
        3)
                curl -A "$user_agent" -Lso 'raspi-mirrors' 'https://raspi-mirrors.optimizethis.net'
                sudo bash 'raspi-mirrors'
                return 0
                ;;
        4)
                curl -A "$user_agent" -Lso 'archlinux-mirrors' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Arch%20Linux%20Scripts/archlinux-mirrors.sh'
                sudo bash 'archlinux-mirrors'
                return 0
                ;;
        5)      return 0;;
        *)
                unset answer
                clear
                main_menu
                ;;
    esac
    clear
}

main_menu
