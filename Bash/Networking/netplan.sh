#!/usr/bin/env bash

clear

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

sudo apt -y install netplan.io
clear


repo=https://github.com/slyfox1186/script-repo
yfile=/etc/netplan/01-netcfg.yaml


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
    if ! sudo netplan apply; then
        fail_fn 'The script failed to apply the settings.'
    fi
}

create_dhcp_yaml_fn() {
    sudo cat > "$yfile" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $con_id:
      dhcp4: yes
EOF

}

create_static_yaml_fn() {
    local ip_address_sed

    sudo cat > "$yfile" <<EOF
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

    ip_address_sed="$(echo "$ip_address" | sed 's/\//\\\//g')"
    dns_master_sed="$(echo "$dns_master" | sed 's/,//g')"
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

cat <<EOF
Connection: $con_id
IP Address: $ip_address
Gateway: $gateway
DNS 1: $dns1
DNS 2: $dns2
DNS 3: $dns3
Method: $dhcp_answer
EOF

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

exit_fn
