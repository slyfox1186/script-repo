#!/usr/bin/env bash

clear

if [ "$EUID" -ne '0' ]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

# UPDATE A BROKEN OF MISSING ESSENTIAL NETWORKING FILE
cat > '/etc/network/interfaces' <<'EOF'
######################################################################
# /etc/network/interfaces -- configuration file for ifup(8), ifdown(8)
#
# A "#" character in the very first column makes the rest of the line
# be ignored. Blank lines are ignored. Lines may be indented freely.
# A "\" character at the very end of the line indicates the next line
# should be treated as a continuation of the current one.
#
# The "pre-up", "up", "down" and "post-down" options are valid for all 
# interfaces, and may be specified multiple times. All other options
# may only be specified once.
#
# See the interfaces(5) manpage for information on what options are 
# available.
######################################################################

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.2.40/24
    netmask 255.255.255.0
    gateway 192.168.2.1
EOF

# SET THE NAMESERVER AS THE IP OF PIHOLE
echo 'nameserver 192.168.2.40' > '/etc/resolv.conf'

# RESTART THE NETWORK SERVICE TO UPDATE THE CHANGES
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
