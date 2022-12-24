#!/bin/sudo bash

clear

echo -e "This script will allow the user to quickly switch Ubuntu Desktop"
echo -e "into it's VGA or Headless Client mode as dictated by the startup"
echo -e "commands located in /etc/default/grub.\\n"
echo -e "This has been only tested on my pc using Ubuntu Jammy 22.04.1"
echo -e "Please run this script at your own risk as I assume none.\\n"
read -p 'Press Enter to continue.'

clear

FILE='/etc/default/grub'

echo '[1] Headless Mode'
echo '[2] VGA Mode'
echo -e "[3] Exit\\n"
read -p 'Enter a number: ' i

clear

if [[ "$i" -eq "1"  ]]; then sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="3"/g' $FILE
elif [[ "$i" -eq "2"  ]]; then sudo sed -i 's/GRUB_CMDLINE_LINUX="3"/GRUB_CMDLINE_LINUX=""/g' $FILE
elif [[ "$i" -eq "3"  ]]; then clear; ls -hF1AX --group-directories-first --color; exit
else
    echo '[i] Input Error: Please from choose one of the following numbers:'
    echo -e "    [1] , [2] , [3]\\n"
    read -p 'Press Enter to start over or Ctrl+C to exit. '
    clear; sudo bash "$0"
    exit 1
fi

clear; unset i

echo -e "Do you want to update grub?\\n"
echo '[1] Yes'
echo -e "[2] No\\n"
read -p 'Enter a number: ' i

clear

if [[ "$i" -eq "1"  ]]; then
    sudo update-grub
    echo
elif [[ "$i" -eq "2"  ]]; then echo ''; fi

unset i
