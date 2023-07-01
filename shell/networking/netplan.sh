#!/bin/bash

clear

if [ "$EUID" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script as root/sudo.'
    exit 1
fi

repo=https://github.com/slyfox1186/script-repo

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

# SET SCRIPT VARIABLES
yaml_file=/etc/netplan/01-netcfg.yaml

# SET FUNCTIONS
create_yaml_fn()
{
    local ip_address_sed
    clear

# CREATE NETPLAN STATIC IP file
    cat > "$yaml_file" <<EOF
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

# THE APT PACKAGE NETPLAN.IO MUST BE INSTALLED
if ! which netplan &>/dev/null; then
	sudo apt -y install netplan.io
    clear
fi

# ECHO THE CHOSEN OPTIONS
cat <<EOF
Connection: $con_id
IP Address: $ip_address
Gateway: $gateway
DNS 1: $dns1
DNS 2: $dns2
DNS 3: $dns3
EOF

# PROMPT USER TO CONTINUE
printf "\n%s\n\n%s\n%s\n\n" \
    'Do you want to execute the script with the above configuration?' \
    '[1] Yes' \
    '[2] No'
read -p 'Your choices are (1 or 2): ' choice
clear

case "$choice" in
    1)      create_yaml_fn;;
    2)      exit 0;;
    *)
            printf "%s\n\n" 'Bad user input.'
            exit 1
            ;;
esac

# CALL FUNCTION TO CREATE FILE
create_yaml_fn

# OPEN AN EDITOR TO VIEW THE CHANGES
if which gedit &>/dev/null; then
    sudo gedit "$yaml_file"
elif which nano &>/dev/null; then
    sudo nano "$yaml_file"
elif which vim &>/dev/null; then
    sudo vim "$yaml_file"
elif which vi &>/dev/null; then
    sudo vi "$yaml_file"
else
    clear
fi

# EXECUTE NETPLAN AND APPLY THE SETTINGS
if ! sudo netplan apply; then
    printf "%s\n\n%s\n%s\n\n" \
    'The script failed to apply the settings!' \
    'Create an issue at:' \
    "$repo/issues"
    exit 1
fi
