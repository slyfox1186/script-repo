#!/usr/bin/env bash

clear

if [ "$EUID" -ne '0' ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

cat > '/etc/network/interfaces' <<'EOF'

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.2.40/24
    netmask 255.255.255.0
    gateway 192.168.2.1
EOF

echo 'nameserver 192.168.2.40' > '/etc/resolv.conf'

if ! sudo /etc/init.d/networking restart; then
    clear
    printf "%s\n\n" "Failed to execute the command: sudo /etc/init.d/networking restart. Line: $LINENO"
    exit 1
fi

clear
printf "%s\n\n" 'Checking if networking is back online.'
if ! ping 8.8.8.8; then
    printf "%s\n\n" 'Failed to ping google.'
else
    printf "%s\n\n" 'We are back online baby!'
fi
