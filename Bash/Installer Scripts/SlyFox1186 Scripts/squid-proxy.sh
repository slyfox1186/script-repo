#!/Usr/bin/env bash

clear

if [ "$EUID" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script as root/sudo'
    exit 1
fi


if [ ! -d /etc/squid ]; then
    sudo mkdir -p /etc/squid
fi

if ! systemctl status squid.service; then
    printf "%s\n\n%s\n\n" \
        'The squid service needs to be running to continue.'
        'The script will attempt to start squid now... please be patient.'
    sudo service squid start
fi
if ! service squid start; then
    printf "%s\n\n%s\n\n" \
        'The script was unable to start the squid service. You should manually change any errors'
        'in the squid.conf file which is usually located in "/etc/squid/squid.conf"'
    exit 1
else
    clear
    printf "%s\n\n" 'Started Squid'
    sleep 2
    clear
fi

squid_user=proxy
hostname=homebridge

sd_tout='5 seconds'

client_pcons=on
server_pcons=off


cache_dir_squid=/var/spool/squid
cache_dir_squid_size=1000
cache_swp_high=95
cache_swp_low=90
mem_cache_mode=always
cache_mem='512 MB'

client_rqst_bfr_size='512 KB'

squid_port=3128/tcp
pihole_port=4711/tcp

Fwld_01=dhcp
Fwld_02=dhcpv6
Fwld_03=dns
Fwld_04=http
Fwld_05=ssh

dns_server_ip=192.168.1.40

min_obj_size='64 bytes'
max_obj_size='1 MB'
max_obj_size_mem='1 MB'

basic_ncsa_auth="$(sudo find /usr/lib -type f -name basic_ncsa_auth)"
squid_config=/etc/squid/squid.conf
squid_passwords=/etc/squid/passwords
squid_whitelist=/etc/squid/whitelist.txt
squid_blacklist=/etc/squid/blacklist.txt

detect_broken_pconn=off

cat > "$squid_config" <<EOF































































acl SSL_ports port 443

acl whitelist dstdomain $squid_whitelist
acl blacklist dstdomain squid_blacklist










http_access deny !Safe_ports

http_access allow !SSL_ports

http_access allow localhost manager
http_access deny manager

http_access deny to_localhost

include /etc/squid/conf.d/*


include /etc/squid/conf.d/*
auth_param basic program $basic_ncsa_auth $squid_passwords
auth_param basic realm proxy
auth_param basic children 5
acl authenticated proxy_auth REQUIRED
acl github dstdomain .github.com
cache deny github

http_access deny !authenticated
http_access allow localnet
http_access allow localhost
http_access allow whitelist

http_access deny blacklist
http_access deny all

client_request_buffer_max_size $client_rqst_bfr_size

dns_nameservers $dns_server_ip

minimum_object_size $min_obj_size
maximum_object_size $max_obj_size
maximum_object_size_in_memory $max_obj_size_mem

cache_swap_low $cache_swp_low
cache_swap_high $cache_swp_high

memory_cache_mode $mem_cache_mode

cache_dir ufs $cache_dir_squid $cache_dir_squid_size 16 256

refresh_pattern \/master$                                    0         0%        0  refresh-ims
refresh_pattern ^ftp:                                     1440        20%    10080
refresh_pattern ^gopher:                                  1440         0%     1440
refresh_pattern -i (/cgi-bin/|\?)                            0         0%        0
refresh_pattern \/(Packages|Sources)(|\.bz2|\.gz|\.xz)$      0         0%        0  refresh-ims
refresh_pattern \/Release(|\.gpg)$                           0         0%        0  refresh-ims
refresh_pattern \/InRelease$                                 0         0%        0  refresh-ims
refresh_pattern \/(Translation-.*)(|\.bz2|\.gz|\.xz)$        0         0%        0  refresh-ims
refresh_pattern (\.deb|\.udeb)$                         129600       100%   129600
refresh_pattern .                                            0        20%     4320

cache_mem $cache_mem

http_port 3128

visible_hostname $hostname

detect_broken_pconn $detect_broken_pconn
client_persistent_connections $client_pcons
server_persistent_connections $server_pcons

cache_effective_user $squid_user

http_accel_surrogate_remote on
esi_parser expat

shutdown_lifetime $sd_tout





















































































coredump_dir /var/spool/squid




























































































umask 022





















































































































































































EOF

cat > "$squid_whitelist" <<EOF
192.168.1.40
.github.com
.google.com
.gmail.com
EOF

cat > "$squid_blacklist" <<EOF
.tiktok.com
.whatsapp.com
EOF

if ! which htpasswd; then
    sudo apt -y install apache2-utils
    clear
fi

if [ ! -f "$squid_passwords" ]; then
    if ! htpasswd -c "$squid_passwords" squid; then
        printf "\n%s\n\n" 'The squid passwd file failed to create.'
    else
        printf "\n%s\n\n" 'The squid passwd file was created successfully!'
    fi
    sleep 3
    echo
    "$(type -P cat)" "$squid_passwords"
fi

printf "\n%s\n%s\n\n" \
    '[1] Add IPTables and UFW firewall rules' \
    '[2] Skip'
read -p 'Enter a number: ' choice
clear

case "$choice" in
    1)
            printf "%s\n%s\n\n" \
                'Installing IPTABLES Firewall Rules' \
                '===================================='
            iptables -I INPUT 1 -s 192.168.0.0/16 -p tcp -m tcp --dport 80 -j ACCEPT
            iptables -I INPUT 1 -s 127.0.0.0/8 -p tcp -m tcp --dport 53 -j ACCEPT
            iptables -I INPUT 1 -s 127.0.0.0/8 -p udp -m udp --dport 53 -j ACCEPT
            iptables -I INPUT 1 -s 192.168.0.0/16 -p tcp -m tcp --dport 53 -j ACCEPT
            iptables -I INPUT 1 -s 192.168.0.0/16 -p udp -m udp --dport 53 -j ACCEPT
            iptables -I INPUT 1 -p udp --dport 67:68 --sport 67:68 -j ACCEPT
            iptables -I INPUT 1 -p tcp -m tcp --dport 4711 -i lo -j ACCEPT
            iptables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
            ip6tables -I INPUT -p udp -m udp --sport 546:547 --dport 546:547 -j ACCEPT
            ip6tables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
            printf "\n%s\n%s\n\n" \
                'Installing UFW Firewall Rules'
                '=============================='
            ufw allow 53/tcp
            ufw allow 53/udp
            ufw allow 67/tcp
            ufw allow 67/udp
            ufw allow 80/tcp
            ufw allow 546:547/udp
            echo
            read -p 'Press enter to continue.'
            clear
            ;;
    2)      clear;;
    '')     clear;;
    *)
            printf "%s\n\n" 'Bad user input.'
            exit 1
            ;;
esac

sudo squid -k reconfigure

sudo service squid restart
clear

if ! which squidclient &>/dev/null; then
    sudo apt -y install squidclient
fi

squidclient https://google.com
