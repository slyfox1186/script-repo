#!/usr/bin/env bash

clear

user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36'

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

box_out_banner()
{
    input_char=$(echo "${@}" | wc -c)
    line=$(for i in $(seq 0 ${input_char}); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)${line}"
    space=${line//-/ }
    echo " ${line}"
    printf '|'; echo -n "${space}"; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "${@}"; tput setaf 3; printf "%s\n" ' |';
    printf '|'; echo -n "${space}"; printf "%s\n" '|';
    echo " ${line}"
    tput sgr 0
}
box_out_banner 'Installer Script Menu'

#
# DOWNLOAD SCRIPTS
#

szip_release_fn() { bash <(curl -A "${user_agent}" -fsSL 'https://7z.optimizethis.net'); }
dl_tools_fn() { bash <(curl -A "${user_agent}" -fsSL 'https://dl-tools.optimizethis.net'); }
build_tools_fn() { bash <(curl -A "${user_agent}" -fsSL 'https://build-tools.optimizethis.net'); }
magick_fn() { bash <(curl -A "${user_agent}" -fsSL 'https://magick.optimizethis.net'); }
ffmpeg_fn() { bash <(curl -A "${user_agent}" -fsSL 'https://build-ffmpeg.optimizethis.net') --build --latest; }
gparted_fn() { bash <(curl -A "${user_agent}" -fsSL 'https://gparted.optimizethis.net'); }
deb_dl_fn() { bash <(curl -A "${user_agent}" -fsSL 'https://download.optimizethis.net'); }
video_fn() { bash <(curl -A "${user_agent}" -fsSL 'https://players.optimizethis.net'); }

#
# DISPLAY THE CUSTOM USER SCRIPTS MENU
#

custom_user_scripts()
{
    local answer
echo -ne "
$(ColorGreen '1)')  Ubuntu Lunar
$(ColorGreen '2)')  Ubuntu Jammy, Focal, or Bionic
$(ColorGreen '3)')  Ubuntu Lunar
$(ColorGreen '0)')  Exit
$(ColorBlue 'Choose an option:') "
    read answer
    clear
    case "${answer}" in
        1)
                bash <(curl -A "${user_agent}" -fsSL 'https://lunar-scripts.optimizethis.net')
                unset answer
                clear
                main_menu
                ;;
        2)
                bash <(curl -A "${user_agent}" -fsSL 'https://jammy-scripts.optimizethis.net')
                unset answer
                clear
                main_menu
                ;;
        3)
                bash <(curl -A "${user_agent}" -fsSL 'https://raspi-scripts.optimizethis.net')
                unset answer
                clear
                main_menu
                ;;
        0)      main_menu;;
        *)
                unset answer
                clear
                custom_user_scripts
                ;;
    esac
}

#
# DISPLAY THE EXTRA MIRRORS MENU
#

extra_mirrors()
{
    local answer
echo -ne "
$(ColorGreen '1)')  Ubuntu Lunar
$(ColorGreen '2)')  Ubuntu Jammy
$(ColorGreen '3)')  Ubuntu Focal
$(ColorGreen '4)')  Ubuntu Bionic
$(ColorGreen '5)')  Debian Bullseye
$(ColorGreen '6)')  Debian Bookworm
$(ColorGreen '0)')  Exit
$(ColorBlue 'Choose an option:') "
    read answer
    clear
    case "${answer}" in
        1)
                curl -A "${user_agent}" -Lso 'lunar-mirrors.sh' 'https://lunar-mirrors.optimizethis.net'
                sudo bash 'lunar-mirrors.sh'
                unset answer
                clear
                main_menu
                ;;
        2)
                curl -A "${user_agent}" -Lso 'jammy-mirrors.sh' 'https://jammy-mirrors.optimizethis.net'
                sudo bash 'jammy-mirrors.sh'
                unset answer
                clear
                main_menu
                ;;
        3)
                curl -A "${user_agent}" -Lso 'focal-mirrors.sh' 'https://focal-mirrors.optimizethis.net'
                sudo bash 'focal-mirrors.sh'
                unset answer
                clear
                main_menu
                ;;
        4)
                curl -A "${user_agent}" -Lso 'bionic-mirrors.sh' 'https://bionic-mirrors.optimizethis.net'
                sudo bash 'bionic-mirrors.sh'
                unset answer
                clear
                main_menu
                ;;
        5)
                curl -A "${user_agent}" -Lso 'bullseye-mirrors.sh' 'https://bullseye-mirrors.optimizethis.net'
                sudo bash 'bullseye-mirrors.sh'
                unset answer
                clear
                main_menu
                ;;
        6)
                curl -A "${user_agent}" -Lso 'bookworm-mirrors.sh' 'https://bookworm-mirrors.optimizethis.net'
                sudo bash 'bookworm-mirrors.sh'
                unset answer
                clear
                main_menu
                ;;
        0)
                unset answer
                clear
                main_menu
                ;;
        *)
                unset answer
                clear
                extra_mirrors
                ;;
    esac
}

#
# DISPLAY THE MAIN MENU
#

main_menu()
{
    printf "%s\n\n" 'If you choose a build script it will be sourced from the latest version available.'
    local answer
echo -ne "
$(ColorGreen '1)')  7-Zip v23.01
$(ColorGreen '2)')  cURL, WGET and Aria2c
$(ColorGreen '3)')  CMake, Meson, Ninja, and GoLang
$(ColorGreen '4)')  ImageMagick 7
$(ColorGreen '5)')  FFmpeg (This is a large script, be prepared to sit back for a while)
$(ColorGreen '6)')  GParted with all optional libraries
$(ColorGreen '7)')  Video Players
$(ColorGreen '8)')  Custom User Scripts (.bashrc, .bash_aliases, .bash_functions) Warning! This will overwrite your files!
$(ColorGreen '9)')  Extra Source Mirrors (/etc/apt/sources.list) Warning! This will overwrite your files!
$(ColorGreen '10)') APT to Debian Package Downloader
$(ColorGreen '0)')  Exit
$(ColorBlue 'Choose an option:') "
    read answer
    clear
    case "${answer}" in
        1)
                szip_release_fn
                unset answer
                clear
                main_menu
                ;;
        2)
                dl_tools_fn
                unset answer
                clear
                main_menu
                ;;
        3)
                build_tools_fn
                unset answer
                clear
                main_menu
                ;;
        4)
                magick_fn
                unset answer
                clear
                main_menu
                ;;
        5)
                ffmpeg_fn
                unset answer
                clear
                main_menu
                ;;
        6)
                gparted_fn
                unset answer
                clear
                main_menu
                ;;
        7)
                video_fn
                unset answer
                clear
                main_menu
                ;;
        8)
                custom_user_scripts
                unset answer
                clear
                main_menu
                ;;
        9)
                extra_mirrors
                unset answer
                clear
                main_menu
                ;;
        10)
                deb_dl_fn
                unset answer
                clear
                main_menu
                ;;
        0)      exit 0;;
        *)
                unset answer
                clear
                main_menu
                ;;
    esac
}
main_menu
