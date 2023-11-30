#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2162

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
    printf "%s\n\n" 'No need to backup the original file as it has already been done.'
fi
sleep 4
clear

activate_fn()
{
    if [ -n "${1}" ]; then
        add_ns="$(dns-nameservers "${1}")"
    fi

cat > "${fname}" <<EOF
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto ${interface}
iface ${interface} inet static
    address ${address}
    netmask ${netmask}
    broadcast ${broadcast}
    gateway ${gateway}
    ${add_ns}
EOF
}

cnt=1

get_input_fn()
{
    read -p 'Enter Network Interface: (eth0): '  interface
    read -p 'Enter Static IP: (192.168.2.40): '  address
    read -p 'Enter Netmask: (255.255.255.0): '   netmask
    read -p 'Enter Broadcast: (192.168.2.255): ' broadcast
    read -p 'Enter Gateway: (192.168.2.1): '     gateway
    clear

    while true
    do
        ((cnt++))
        read -p "Enter Nameserver: (1.1.1.1): "  nameserver$cnt
        while true
        do
            read -p 'Enter another? yes/no: ' reply
            case "${reply}" in
                Y|y|Yes|yes|"")     break;;
                N|n|No|no)          break 2;;
                *)
                                    clear
                                    printf "%s\n\n" 'Bad user input. If you want more nameservers, re-run the script or wait 5 seconds to continue.'
                                    sleep 5
                                    return 0
                                    ;;
            esac
        done
    done
}
get_input_fn

clear

case "${cnt}" in
    1)      ns_cnt="${nameserver1}";;
    2)      ns_cnt="${nameserver1} ${nameserver2}";;
    3)      ns_cnt="${nameserver1 }${nameserver2} ${nameserver3}";;
    4)      ns_cnt="${nameserver1} ${nameserver2} ${nameserver3} ${nameserver4}";;
esac

printf "%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n\n"   \
    'The pending values are shown below...' \
    "Network Interface: ${interface}"       \
    "Static IP:         ${address}"         \
    "Netmask:           ${netmask}"         \
    "Broadcast:         ${broadcast}"       \
    "Gateway:           ${gateway}"         \
    "Nameserver(s):     ${ns_cnt}"
    
read -p 'Press [1] to proceed [2] to exit: ' choice
clear

case "${choice}" in
    1)      activate_fn "${ns_cnt}";;
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