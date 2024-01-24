#!/usr/bin/env bash
# shellcheck disable=SC2000,SC2034,SC2162

clear

#
# INSTALL CURL
#

if ! sudo dpkg -l | grep -o curl &>/dev/null; then
    sudo apt -y install curl
fi

#
# CREATE SCRIPT VARIABLES
#

export user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
green='\e[32m'
blue='\e[34m'
clear='\e[0m'

#
# MENU COLOR FUNCTIONS
#

ColorGreen() { echo -ne "${green}${1}${clear}"; }
ColorBlue() { echo -ne "${blue}${1}${clear}"; }

#
# SHOW SCRIPT BANNER
#

function box_out_banner()
{
    input_char=$(echo "${@}" | wc -c)
    line=$(for i in $(seq 0 "${input_char}"); do printf '-'; done)
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
box_out_banner 'Install User Scripts'

#
# DISPLAY THE MAIN MENU
#

main_menu()
{
    local answer
echo -ne "
$(ColorGreen '1)') Debian 10/11/12
$(ColorGreen '2)') Ubuntu (18/20/22).04
$(ColorGreen '3)') Ubuntu 23.04
$(ColorGreen '4)') Arch Linux
$(ColorGreen '5)') Raspberry Pi
$(ColorGreen '0)') Exit
$(ColorBlue 'Choose the operating system:') "
    read answer
    clear

    case "${answer}" in
        1)      bash <(curl -A "${user_agent}" -fsSL 'https://bookworm-scripts.optimizethis.net');;
        2)      bash <(curl -A "${user_agent}" -fsSL 'https://jammy-scripts.optimizethis.net');;
        3)      bash <(curl -A "${user_agent}" -fsSL 'https://lunar-scripts.optimizethis.net');;
        4)      bash <(curl -A "${user_agent}" -fsSL 'https://arch-scripts.optimizethis.net');;
        5)      bash <(curl -A "${user_agent}" -fsSL 'https://raspi-scripts.optimizethis.net');;
        0)      return 0;;
        *)
                unset answer
                clear
                main_menu
                ;;
    esac
}
main_menu
