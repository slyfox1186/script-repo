#!/usr/bin/env bash

clear

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

if ! sudo dpkg -l | grep -o 'lighttpd' &>/dev/null; then
    sudo apt -y install lighttpd
    clear
fi

if [ -z "$1" ]; then
    clear
    read -p 'Please enter the new listening port for Pi-Hole (example: 20000): ' custom_port
    clear
else
    custom_port="$1"
fi

echo "server.port := $custom_port" | sudo tee '/etc/lighttpd/conf-available/04-external.conf' >/dev/null

cd '/etc/lighttpd/conf-enabled' || exit 1
sudo ln -sf '../conf-available/04-external.conf' '04-external.conf'
sudo systemctl restart lighttpd.service
clear

pihole_ip="$(ip route get 1.2.3.4 | awk '{print $7}')"

printf "%s\n\n%s\n\n"                              \
    'Pi-Hole'\''s new web address is shown below.' \
    "http://$pihole_ip:$custom_port/admin"
