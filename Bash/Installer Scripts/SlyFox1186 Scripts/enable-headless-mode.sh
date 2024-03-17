#!/Usr/bin/env bash

clear

echo 'This script will allow the user to quickly switch Ubuntu Desktop'
echo 'into it'\''s VGA or Headless Client mode as dictated by the startup'
echo 'commands located in /etc/default/grub.'
echo
echo 'This has been only tested on my pc using Ubuntu Jammy 22.04.1'
echo
echo 'Run this script at your own risk as I assume none.'
echo
read -p 'Press enter to continue.'
clear

file='/etc/default/grub'

if [ ! "$file" ]; then
    echo "The main file: $file was not found."
    echo
    exit 1
fi

echo '[1] Headless Mode'
echo '[2] VGA Mode'
echo '[3] Exit'
echo
read -p 'Your choices are ( 1 to 3): ' i

clear

if [[ "$i" -eq '1'  ]]; then sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="3"/g' "$file"
elif [[ "$i" -eq '2'  ]]; then sed -i 's/GRUB_CMDLINE_LINUX="3"/GRUB_CMDLINE_LINUX=""/g' "$file"
elif [[ "$i" -eq '3'  ]]; then clear; \ls -1AhFv --group-directories-first --color; exit
else
    echo 'Input error: enter a number (1 to 3)'
    echo
    read -p 'Press enter to start over or Ctrl+Z to exit: '
    clear
    bash "$0"
fi

clear
unset i

echo 'Do you want to update grub?'
echo
echo '[1] Yes'
echo '[2] No'
echo
read -p 'Enter a number: ' i

clear

if ! update-grub; then
    echo 'The update-grub command failed.'
    echo
    exit 1
fi
