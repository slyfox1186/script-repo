#!/usr/bin/env bash

clear

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

sudo apt -y install netplan.io
clear

#
# SET SCRIPT VARIABLES
#

repo=https://github.com/slyfox1186/script-repo
yfile=/etc/netplan/01-netcfg.yaml

#
# CREATE FUNCTIONS
#

exit_fn() {
    clear
    printf "%s\n\n%s\n%s\n\n" \
        'The script has completed!' \
        'Make sure to star this repository to show your support!' \
        "$repo"
    exit 0
}

fail_fn() {
    printf "\n%s\n\n%s\n\n%s\n\n" \
        "$1" \
        'Please report this at:' \
        "$repo/issues"
    exit 1
}

apply_settings_fn() {
    # EXECUTE NETPLAN AND APPLY THE SETTINGS
    if ! sudo netplan apply; then
        fail_fn 'The script failed to apply the settings.'
    fi
}

create_dhcp_yaml_fn() {
    sudo cat > "$yfile" <<EOF
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: networkd
  ethernets:
    $con_id:
      dhcp4: yes
EOF

    # RASPBIAN BULLSEYE HAS A BUG WHERE TWO IP ADDRESSES WILL BE SHOWN WHEN RUNNING COMMAND 'ip a'
    # THIS CHANGES THE DHCP CONFIG FILE AND SEEMS TO FIX THE ISSUE AFTER A REBOOT
    sudo sed -Ei "s/^interface/#interface/g" /etc/dhcpcd.conf
    sudo sed -Ei "s/^static ip_address=/#static ip_address=/g" /etc/dhcpcd.conf
    sudo sed -Ei "s/^static routers=/#static routers=/g" /etc/dhcpcd.conf
    sudo sed -Ei "s/^static domain_name_servers=/#static domain_name_servers=/g" /etc/dhcpcd.conf
}

create_static_yaml_fn() {
    local ip_address_sed

# CREATE NETPLAN STATIC IP file
    sudo cat > "$yfile" <<EOF
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: networkd
  ethernets:
    $con_id:
      addresses:
        - $ip_address
      gateway4: $gateway
      nameservers:
          addresses: [$dns_master]
EOF

    # RASPBIAN BULLSEYE HAS A BUG WHERE TWO IP ADDRESSES WILL BE SHOWN WHEN RUNNING COMMAND 'ip a'
    # THIS CHANGES THE DHCP CONFIG FILE AND SEEMS TO FIX THE ISSUE AFTER A REBOOT
    ip_address_sed="$(echo "$ip_address" | sed 's/\//\\\//g')"
    dns_master_sed="$(echo "$dns_master" | sed 's/,//g')"
    sudo sed -i "0,/^#interface $con_id/s//interface $con_id/" /etc/dhcpcd.conf
    sudo sed -Ei "0,/^#static ip_address=(.*)$/s//static ip_address=$ip_address_sed/" /etc/dhcpcd.conf
    sudo sed -Ei "0,/^#static routers=(.*)$/s//static routers=$gateway/" /etc/dhcpcd.conf
    sudo sed -Ei "0,/^#static domain_name_servers=(.*)$/s//static domain_name_servers=$dns_master_sed/" /etc/dhcpcd.conf
}

sort_method_fn() {
    if [ "$dhcp_answer" = 'Static IP' ]; then
        create_static_yaml_fn
    elif [ "$dhcp_answer" = 'DHCP' ]; then
        create_dhcp_yaml_fn
    fi
}

set_dhcp_fn() {
    printf "%s\n\n" 'Please enter the desired IP settings.'
    read -p 'Connection Name (example: eth0): ' con_id
    clear
}

set_static_fn() {
    # PROMPT THE USER TO INPUT THE IP SETTINGS
    printf "%s\n\n" 'Please enter the desired IP settings.'
    read -p 'Connection Name (example: eth0): ' con_id
    read -p 'IPv4 Address (example: xxx.xxx.xxx.xxx/xx): ' ip_address
    read -p 'Gateway (example: xxx.xxx.xxx.xxx): ' gateway
    read -p 'Nameserver 1 (example: 192.168.1.1): ' dns1
    read -p 'Nameserver 2 (example: 1.1.1.1 or leave blank): ' dns2
    read -p 'Nameserver 3 (example: 1.0.0.1 or leave blank): ' dns3
    clear

    if [ -n "$dns1" ] && [ -z "$dns2" ] && [ -z "$dns3" ]; then
        dns_master="$dns1"
    elif [ -n "$dns1" ] && [ -n "$dns2" ] && [ -z "$dns3" ]; then
        dns_master="$dns1, $dns2"
    elif [ -n "$dns1" ] && [ -n "$dns2" ] && [ -n "$dns3" ]; then
        dns_master="$dns1, $dns2, $dns3"
    fi
}

# PROMPT THE USER TO CHOOSE STATIC OR DHCP
printf "\n%s\n\n%s\n%s\n%s\n\n" \
    'Choose a configuration' \
    '[1] DHCP' \
    '[2] Static IP' \
    '[3] Exit'
read -p 'Your choices are (1 to 3): ' choice
clear

case "$choice" in
    1)
            set_dhcp_fn
            dhcp_answer=DHCP
            ;;
    2)
            set_static_fn
            dhcp_answer='Static IP'
            ;;
    *)      fail_fn 'Bad user input.';;
esac
unset choice

# ECHO THE CHOSEN OPTIONS
cat <<EOF
Connection: $con_id
IP Address: $ip_address
Gateway: $gateway
DNS 1: $dns1
DNS 2: $dns2
DNS 3: $dns3
Method: $dhcp_answer
EOF

# PROMPT USER TO CONTINUE
printf "\n%s\n\n%s\n%s\n\n" \
    'Do you want to execute the script with the above configuration?' \
    '[1] Yes' \
    '[2] No'
read -p 'Your choices are (1 or 2): ' choice
clear

case "$choice" in
    1)
            sort_method_fn
            apply_settings_fn
            ;;
    2)      clear;;
    *)      fail_fn 'Bad user input.';;
esac

# SHOW EXIT MESSAGE
exit_fn
