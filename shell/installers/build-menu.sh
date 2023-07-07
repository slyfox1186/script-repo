#!/bin/bash
clear

#
# MENU COLOR FUNCTIONS
#

green='\e[32m'
blue='\e[34m'
clear='\e[0m'
ColorGreen() { echo -ne "$green$1$clear"; }
ColorBlue() { echo -ne "$blue$1$clear"; }

#
# SHOW SCRIPT BANNER
#

function box_out_banner()
{
    input_char=$(echo "$@" | wc -c)
    line=$(for i in `seq 0 $input_char`; do printf "-"; done)
    tput bold
    line="$(tput setaf 3)${line}"
    space=${line//-/ }
    echo " ${line}"
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    echo " ${line}"
    tput sgr 0
}

#
# DOWNLOAD SCRIPTS
#

szip_release_fn() { bash <(curl -sSL https://7z.optimizethis.net); }
dl_tools_fn() { bash <(curl -sSL https://dl-tools.optimizethis.net); }
build_tools_fn() { bash <(curl -sSL https://build-tools.optimizethis.net); }
magick_fn() { bash <(curl -sSL https://magick.optimizethis.net) --build --latest; }
ffmpeg_fn() { bash <(curl -sSL https://build-ffmpeg.optimizethis.net) --build --enable-gpl-and-non-free --latest; }
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
    case "$answer" in
        1)
            bash <(curl -sSL https://lunar-scripts.optimizethis.net)
            clear
            main_menu
            ;;
        2)
            bash <(curl -sSL https://jammy-scripts.optimizethis.net)
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
    case "$answer" in
        1)
            curl -Lso mirrors https://lunar-mirrors.optimizethis.net; sudo bash mirrors
            clear
            main_menu
            ;;
        2)
            curl -Lso mirrors https://jammy-mirrors.optimizethis.net; sudo bash mirrors
            clear
            main_menu
            ;;
        3)
            curl -Lso mirrors https://focal-mirrors.optimizethis.net; sudo bash mirrors
            clear
            main_menu
            ;;
        4)
            curl -Lso mirrors https://bionic-mirrors.optimizethis.net; sudo bash mirrors
            clear
            main_menu
            ;;
        5)
            curl -Lso mirrors https://bullseye-mirrors.optimizethis.net; sudo bash mirrors
            clear
            main_menu
            ;;
        6)
            curl -Lso mirrors https://bookworm-mirrors.optimizethis.net; sudo bash mirrors
            clear
            main_menu
            ;;
        0)  main_menu;;
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
$(ColorGreen '1)')  7-Zip Release v23.01
$(ColorGreen '2)')  cURL, WGET & Aria2c
$(ColorGreen '3)')  CMake, Meson, Ninja, and Golang
$(ColorGreen '4)')  ImageMagick 7
$(ColorGreen '5)')  FFmpeg (This is a large script, be prepared to sit back for a while)
$(ColorGreen '6)')  GParted with all extra packages
$(ColorGreen '7)')  Video Players
$(ColorGreen '8)')  Custom User Scripts
$(ColorGreen '9)')  Extra Source Mirrors
$(ColorGreen '10)') APT to Debian Package Downloader
$(ColorGreen '0)')  Exit
$(ColorBlue 'Choose an option:') "
    read answer
    clear
    case "$answer" in
        1)
            szip_release_fn
            clear
            main_menu
            ;;
        2)
            dl_tools_fn
            clear
            main_menu
            ;;
        3)
            build_tools_fn
            clear
            main_menu
            ;;
        4)
            magick_fn
            clear
            main_menu
            ;;
        5)
            ffmpeg_fn
            clear
            main_menu
            ;;
        6)
            gparted_fn
            clear
            main_menu
            ;;
        7)
            video_fn
            clear
            main_menu
            ;;
        8)
            custom_user_scripts
            clear
            main_menu
            ;;
        9)
            extra_mirrors
            clear
            main_menu
            ;;
        10)
            deb_dl_fn
            clear
            main_menu
            ;;
        0)
            sudo rm "$0"
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
