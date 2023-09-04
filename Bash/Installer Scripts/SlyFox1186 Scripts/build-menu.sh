#!/bin/bash
clear

#
# MENU COLOR FUNCTIONS
#

green='\e[32m'
blue='\e[34m'
clear='\e[0m'
ColorGreen() { echo -ne "$green${1}$clear"; }
ColorBlue() { echo -ne "$blue${1}$clear"; }

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
    printf '|'; echo -n "$space"; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "${@}"; tput setaf 3; printf "%s\n" ' |';
    printf '|'; echo -n "$space"; printf "%s\n" '|';
    echo " ${line}"
    tput sgr 0
}

#
# DOWNLOAD SCRIPTS
#

szip_release_fn() { sudo bash <(curl -sSL https://7z.optimizethis.net); }
dl_tools_fn() { bash <(curl -sSL https://dl-tools.optimizethis.net); }
build_tools_fn() { bash <(curl -sSL https://build-tools.optimizethis.net); }
magick_fn() { bash <(curl -sSL https://magick.optimizethis.net) --build; }
ffmpeg_fn() { bash <(curl -sSL https://build-ffmpeg.optimizethis.net) --build --latest; }
go_fn() { bash <(curl -sSL https://go.optimizethis.net); }
gparted_fn() { bash <(curl -sSL https://gparted.optimizethis.net); }
deb_dl_fn() { bash <(curl -sSL https://download.optimizethis.net); }
video_fn() { bash <(curl -sSL https://players.optimizethis.net); }

box_out_banner 'Installer Script Menu'

#
# DISPLAY THE CUSTOM USER SCRIPTS MENU
#

custom_user_scripts()
{
    local answer
echo -ne "
$(ColorGreen '1)')  Ubuntu Lunar
$(ColorGreen '2)')  Ubuntu Jammy, Focal, or Bionic
$(ColorGreen '0)')  Exit
$(ColorBlue 'Choose an option:') "
    read answer
    clear
    case "${answer}" in
        1)
            bash <(curl -sSL https://lunar-scripts.optimizethis.net)
            unset answer
            clear
            main_menu
            ;;
        2)
            bash <(curl -sSL https://jammy-scripts.optimizethis.net)
            unset answer
            clear
            main_menu
            ;;
        0)  main_menu;;
        *)
            printf "%s\n\n" 'Bad user input. Reloading menu...'
            sleep 2
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
            curl -Lso mirrors.sh https://lunar-mirrors.optimizethis.net; sudo bash mirrors.sh
            unset answer
            clear
            main_menu
            ;;
        2)
            curl -Lso mirrors.sh https://jammy-mirrors.optimizethis.net; sudo bash mirrors.sh
            unset answer
            clear
            main_menu
            ;;
        3)
            curl -Lso mirrors.sh https://focal-mirrors.optimizethis.net; sudo bash mirrors.sh
            unset answer
            clear
            main_menu
            ;;
        4)
            curl -Lso mirrors.sh https://bionic-mirrors.optimizethis.net; sudo bash mirrors.sh
            unset answer
            clear
            main_menu
            ;;
        5)
            curl -Lso mirrors.sh https://bullseye-mirrors.optimizethis.net; sudo bash mirrors.sh
            unset answer
            clear
            main_menu
            ;;
        6)
            curl -Lso mirrors.sh https://bookworm-mirrors.optimizethis.net; sudo bash mirrors.sh
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
            printf "%s\n\n" 'Bad user input. Reloading menu...'
            sleep 2
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
    local answer
echo -ne "
$(ColorGreen '1)')  7-Zip v23.01
$(ColorGreen '2)')  cURL, WGET and Aria2c (Latest releases available)
$(ColorGreen '3)')  CMake, Meson, Ninja, and GoLang (Latest releases available)
$(ColorGreen '4)')  ImageMagick 7 (Latest release available)
$(ColorGreen '5)')  FFmpeg (This is a large script, be prepared to sit back for a while)
$(ColorGreen '6)')  GParted (Includes all support libraries)
$(ColorGreen '7)')  Video Players
$(ColorGreen '8)')  Custom User Scripts [ .bashrc | .bash_aliases | .bash_functions ] (Warning! This will overwrite your files!)
$(ColorGreen '9)')  Extra Source Mirrors [ /etc/apt/sources.list ] (Warning! This will overwrite your files!)
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
        0)
            sudo rm "${0}"
            unset answer
            clear
            exit 0
            ;;
        *)
            printf "%s\n\n" 'Bad user input. Reloading menu...'
            sleep 2
            unset answer
            clear
            main_menu
            ;;
    esac
}

main_menu
