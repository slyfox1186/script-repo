#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

[[ ! -d /etc/squid ]] && mkdir -p "/etc/squid"

create_squid_user() {
    echo "Creating user 'squid'..."
    if ! useradd -m squid; then
        echo "Failed to create user 'squid'."
        exit 1
    else
        echo "User 'squid' created successfully."

        echo "Adding user 'squid' to group 'root'..."
        if ! usermod -aG root squid; then
            echo "Failed to add user 'squid' to group 'root'."
        else
            echo "User 'squid' added to group 'root' successfully."
        fi
    fi
}

# Check if user squid exists
if getent passwd squid &>/dev/null; then
    echo "The user \"squid\" was found"
else
    echo "The user \"squid\" was not found"
    create_squid_user
fi

squid_user=squid

squid_conf="/etc/squid/squid.conf"
squid_passwords="/etc/squid/passwords"
squid_whitelist="/etc/squid/whitelist.txt"
squid_blacklist="/etc/squid/blacklist.txt"

cat > $squid_conf <<EOF
acl localnet src 172.16.0.0/12                  # RFC 1918 local private network [LAN]
acl localnet src 192.168.0.0/16                 # RFC 1918 local private network [LAN]
acl localhost src 127.0.0.1/255.255.255.255
acl local_network src 192.168.1.0/255.255.255.0
acl SSL_ports port 443
acl Safe_ports port 80                          # http
acl Safe_ports port 21                          # ftp
acl Safe_ports port 443                         # https
acl Safe_ports port 70                          # gopher
acl Safe_ports port 210                         # wais
acl Safe_ports port 1025-65535                  # unregistered ports
acl Safe_ports port 280                         # http-mgmt
acl Safe_ports port 488                         # gss-http
acl Safe_ports port 563                         # commonly used (at least at one time) for NNTP (USENET news transfer) over SSL
acl Safe_ports port 591                         # filemaker
acl Safe_ports port 777                         # multiling http
acl CONNECT method CONNECT
acl whitelist dstdom_regex $squid_whitelist
acl blacklist dstdomain $squid_blacklist

http_access allow local_network
http_access allow localnet
http_access allow localhost
http_access allow whitelist

# And finally deny all other access to this proxy
http_access deny blacklist
http_access deny all

via off

client_request_buffer_max_size 512 KB

dns_nameservers 1.1.1.1 1.0.0.1

minimum_object_size 64 bytes
maximum_object_size 1 MB
maximum_object_size_in_memory 1 MB

cache_swap_low 90
cache_swap_high 95
cache_mem 512 MB

memory_cache_mode always

cache_dir ufs /var/spool/squid 1024 16 256

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
cache_mem 512 MB
http_port 3128
visible_hostname macbookpro
detect_broken_pconn off
client_persistent_connections on
server_persistent_connections off
# cache_effective_user proxy
http_accel_surrogate_remote on
esi_parser expat
shutdown_lifetime 5 seconds
coredump_dir /var/spool/squid
umask 022
EOF

cat > $squid_whitelist <<'EOF'
\.7z$
\.deb$
\.debb$
\.exe$
\.flac$
\.mkv$
\.mov$
\.mp3$
\.mp4$
\.py$
\.rar$
\.sh$
\.tar\.[a-z]+$
\.tgz$
\.xml$
\.zip$
^ftp:\/\/
EOF

cat > $squid_blacklist <<'EOF'
.facbook.com
.tiktok.com
.whatsapp.com
EOF

if ! type -P htpasswd; then
    apt -y install apache2-utils
    clear
fi

if [[ ! -f "$squid_passwords" ]]; then
    if ! htpasswd -c "$squid_passwords" "$squid_user"; then
        printf "\n%s\n\n" 'The squid passwd file failed to create.'
    else
        printf "\n%s\n\n" 'The squid passwd file was created successfully!'
    fi
    echo
    cat "$squid_passwords"
fi

echo
echo "[1] Add UFW firewall rules"
echo "[2] Skip"
echo
read -p 'Enter a number: ' choice
clear

case "$choice" in
    1)  echo
        echo "Installing UFW Firewall Rules"
        echo "=============================="
        echo
        ufw allow 53/tcp
        ufw allow 53/udp
        ufw allow 67/tcp
        ufw allow 67/udp
        ufw allow 80/tcp
        ufw allow 546:547/udp
        ufw allow 3128/tcp
        echo
        ;;
    2)  ;;
    "") ;;
    *)  printf "%s\n\n" 'Bad user input.'
        exit 1
        ;;
esac

sudo systemctl restart squid
service squid enable

if ! command -v squidclient &>/dev/null; then
    apt -y install squidclient
fi
