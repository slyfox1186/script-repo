#!/usr/bin/env bash

clear

fname='/etc/network/interfaces'

if [ "${EUID}" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script as root/sudo.'
    exit 1
fi

if [ ! -f "${fname}".bak ]; then
    sudo cp "${fname}" "${fname}".bak
    printf "%s\n\n" 'The interfaces file was just backed up. If required, you can find it in the same folder as the original.'
else
    printf "%s\n\n" 'This file was backed up and is located in the same directory as the original.'
fi
sleep 4
clear

activate_fn()
{
cat > "${fname}" <<EOF
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto ${interface}
iface eth0 inet static
    address ${address}
    netmask ${netmask}
    broadcast ${broadcast}
    gateway ${gateway}
EOF
}


read -p 'Enter Network Interface: (eth0): '  interface
read -p 'Enter Static IP: (192.168.2.40): '  address
read -p 'Enter Netmask: (255.255.255.0): '   netmask
read -p 'Enter Broadcast: (192.168.2.255): ' broadcast
read -p 'Enter Gateway: (192.168.2.1): '     gateway
clear

printf "%s\n\n%s\n%s\n%s\n%s\n%s\n\n"       \
    'The pending values are shown below...' \
    "Network Interface: ${interface}"       \
    "Static IP:         ${address}"         \
    "Netmask:           ${netmask}"         \
    "Broadcast:         ${broadcast}"       \
    "Gateway:           ${gateway}"
read -p 'Press [1] to proceed [2] to exit: ' choice
clear

case "${choice}" in
    1)      activate_fn;;
    2)      exit 0;;
    *)
            clear
            printf "%s\n\n" 'Bad user input. Please re-run the script and start over.'
            exit 1
            ;;
esac

clear

cat "${fname}"


printf "\n%s\n%s\n%s\n\n"                                                                      \
    'The new file contents are shown above.'                                                   \
    'It is recommended to run the below command in order for the new settings to take effect.' \
    'sudo ifdown -a && sudo ifup -a'
