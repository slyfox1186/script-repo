#!/usr/bin/env bash

clear

#
# INSTALL CURL
#

sudo apt-get -qq -y install curl

#
# MENU COLOR FUNCTIONS
#

green='\e[32m'
blue='\e[34m'
clear='\e[0m'
ColorGreen()
{
    echo -ne "${green}${1}${clear}"
}
ColorBlue()
{
    echo -ne "${blue}${1}${clear}"
}

#
# SHOW SCRIPT BANNER
#

function box_out_banner()
{
    input_char=$(echo "${@}" | wc -c)
    line=$(for i in `seq 0 ${input_char}`; do printf "-"; done)
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
$(ColorGreen '0)') Exit
$(ColorBlue 'Choose the operating system:') "
    read answer
    clear
    case "${answer}" in
        1)      bash <(curl -fsSL https://bookworm-scripts.optimizethis.net);;
        2)      bash <(curl -fsSL https://jammy-scripts.optimizethis.net);;
        3)      bash <(curl -fsSL https://lunar-scripts.optimizethis.net);;
        0)      return 0;;
        *)      main_menu;;
    esac
}
main_menu
