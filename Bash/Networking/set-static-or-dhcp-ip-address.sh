#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2162

clear

if [ "$EUID" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script as root/sudo.'
    exit 1
fi

#
# CREATE GLOBAL SCRIPT VARIABLES
#

fname='/etc/network/interfaces'
cnt=0

#
# DISPLAY THE USER ASSUMPTION OF LIABILITY PROMPT
#

printf "%s\n\n" 'Disclaimer:'

printf "%s\n\n%s\n%s\n\n" \
    'I take NO responsibility for your system'\''s internet not working after running this script. By continuing, you AGREE to this and fully understand the implications, and will not hold me accountable for any damages suffered on your behalf!' \
    '[1] I fully understand and agree to continue using this script.' \
    '[2] I want to exit this script and not go any further.'
read -p 'Your choices are (1 or 2): ' user_agreement
clear

case "$user_agreement" in
    1)      clear;;
    2)
            clear
            printf "%s\n\n" 'You have chosen to exit the script. Thank you for making the choice you believe was in your best interest - slyfox1186'
            exit 0
            ;;
esac

if [ ! -f "$fname".bak ]; then
    sudo cp "$fname" "$fname".bak
    printf "%s\n\n" 'The "interfaces" file was just backed up as: interfaces.bak. You can find it in the same folder as the original.'
    read -p 'Press enter to continue.'
    clear
fi

show_changes_fn() {
    #
    # PRINT THE CONTENTS OF THE UPDATED INTERFACE FILE
    #

    clear
    printf "%s\n\n%s\n\n"                                     \
        'The new "interfaces" file contents are shown below.' \
        '=================================================================================='
    cat "$fname"

    #
    # PRINT INSTRUCTIONS AND OTHER INFO TO THE USER
    #

    printf "\n%s\n\n%s\n\n%s\n\n%s\n%s\n\n"                                                                      \
        '=================================================================================='                     \
        'To activate the changes you must reboot your PC or execute commands such as "sudo if down; sudo if up"' \
        'Would you like the script to activate the changes now?'                                                 \
        '[1] Yes'                                                                                                \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' enable_choice
    clear

    case "$enable_choice" in
        1)
                # BRING DOWN THE USER-CHOSEN NETWORK INTERFACE
                sudo ifdown "$interface"
                # CLEAR ANY CACHES THAT WOULD INTERFERE WITH THE IFUP COMMAND COMPLETING SUCCESSFULLY
                sudo ip addr flush dev "$interface" 2>&1
                # BRING UP THE NETWORK
                sudo ifup "$interface"
                ;;
        2)      exit 0;;
    esac
}

activate_static_fn() {
    if [ -n "$1" ]; then
        add_ns="dns-nameservers $1"
    fi

    cat > "$fname" <<EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto $interface
iface $interface inet static
    address $address
    netmask $netmask
    broadcast $broadcast
    gateway $gateway
    $add_ns
EOF
}

activate_dhcp_fn() {
    cat > "$fname" <<EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto $interface
iface $interface inet dhcp
EOF
}

choose_type_fn() {
    printf "%s\n\n%s\n%s\n\n"                  \
        'Choose the type of network interface' \
        '[1] DHCP'                             \
        '[2] Static IP'
    read -p 'Your choices are (1 or 2): ' type_choice
    clear

    case "$type_choice" in
        1)
                read -p 'Enter Network Interface: (eth0): '  interface
                activate_dhcp_fn
                show_changes_fn
                exit 0
                ;;
        2)      clear;;
        *)
                unset type_choice
                clear
                choose_type_fn
                ;;
    esac
}
choose_type_fn

#
# PROMPT THE USER TO INPUT THE NETWORK SETTINGS
#

clear
read -p 'Enter Network Interface: (eth0): '  interface
read -p 'Enter Static IP: (192.168.2.40): '  address
read -p 'Enter Netmask: (255.255.255.0): '   netmask
read -p 'Enter Broadcast: (192.168.2.255): ' broadcast
read -p 'Enter Gateway: (192.168.2.1): '     gateway
clear

set_namservers_fn() {
    printf "%s\n\n" 'You may enter (0 to 4) nameservers. To use no nameservers, input the number "0" when first prompted.'
    while [ "$cnt" -lt '4' ]
    do
        ((cnt++))
        read -p "Enter Nameserver: (1.1.1.1): "  nameserver$cnt
        while true
        do
            if [[ "$nameserver1" == '0' ]]; then
                unset nameserver1
                clear
                break 2
            fi
            clear
            read -p 'Enter another? yes/no: ' reply
            clear
            case "$reply" in
                [yY][eE][sS]|[yY]|"")       break;;
                [nN][oO]|[nN])              break 2;;
                *)
                                            clear
                                            printf "%s\n\n" 'Bad user input. Please re-run the script.'
                                            sleep 5
                                            exit 1
                                            ;;
            esac
        done
    done
}
set_namservers_fn

case "$cnt" in
    1)      ns_cnt="$nameserver1";;
    2)      ns_cnt="$nameserver1 $nameserver2";;
    3)      ns_cnt="$nameserver1 $nameserver2 $nameserver3";;
    4)      ns_cnt="$nameserver1 $nameserver2 $nameserver3 $nameserver4";;
esac

clear
printf "%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n\n"   \
    'The pending values are shown below...' \
    "Interface:         $interface"       \
    "Static IP:         $address"         \
    "Netmask:           $netmask"         \
    "Broadcast:         $broadcast"       \
    "Gateway:           $gateway"         \
    "Nameserver:        $ns_cnt"

printf "\n%s\n\n%s\n%s\n\n"                 \
    'Direct the script on what to do next.' \
    '[1] Make the changes shown above.'     \
    '[2] Exit, making no changes.'
read -p 'Your choices are (1 or 2): ' choice
clear

case "$choice" in
    1)      activate_static_fn "$ns_cnt";;
    2)      exit 0;;
    *)
            clear
            printf "%s\n\n" 'Bad user input. Please re-run the script and start over.'
            exit 1
            ;;
esac
