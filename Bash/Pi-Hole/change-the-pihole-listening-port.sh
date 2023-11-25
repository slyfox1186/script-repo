#!/usr/bin/env bash

clear

if [ "${EUID}" -eq '0' ]; then
    printf "%s\n\n" 'You must run this script WITHOUT root/sudo.'
    exit 1
fi

#
# IF NOT INSTALLED, INSTALL LIGHTTPD
#

if ! sudo dpkg -l | grep -o 'lighttpd' &>/dev/null; then
    sudo apt -y install lighttpd
    clear
fi

pihole_ip="$(ip route get 1.2.3.4 | awk '{print $7}')"

# CHECK TO SEE IF YOU PASSED THE NEW PORT NUMBER AS THE FIRST ARGUMENT TO THE SCRIPT
if [ -z "${1}" ]; then
    clear
    read -p 'Please enter the new listening port for Pi-Hole (example: 20000): ' custom_port
    clear
else
    custom_port="${1}"
fi

#
# MODIFY LIGHTHTTPD'S CONFIG FILE PORT NUMBER
#

if ! sudo sed -E -i "s/^server\.port                 \= [0-9]+/server\.port                 = ${custom_port}/g" '/etc/lighttpd/lighttpd.conf'; then
    printf "%s\n\n" 'Failed to modify: /etc/lighttpd/lighttpd.conf'
    exit 1
fi

#
# WHITELIST THE NEW PORT NUMBER IN UFW SO SSH DOESN'T STOP WORKING
#

clear
if ! sudo dpkg -l | grep -o 'ufw' &>/dev/null; then
    sudo apt -y install ufw
fi
sudo ufw allow "${custom_port}"/tcp

#
# RESTART APACHE2 IF INSTALLED
#

if sudo dpkg -l | grep -o 'apache2' &>/dev/null; then
    sudo service apache2 restart
fi

#
# RESTART LIGHTTPD FOR THE CHANGES TO TAKE EFFECT
#

sudo service lighttpd restart

#
# DISPLAY THE UPDATED PIHOLE WEB GUI URL FOR THE USER TO VIEW
#

clear
printf "%s\n\n%s\n\n"                            \
    'Pi-Hole'\''s new web address is show below' \
    "http://${pihole_ip}:${custom_port}/admin"
