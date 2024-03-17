#!/usr/bin/env bash

clear


systemctl status squid.service
if ! systemctl status squid.service; then
    echo -e "Squid service needs to be running to continue! Starting Squid now!\\n"
    sleep 2
    service squid start
    if ! service squid start; then exit 1; fi
else
    echo
    read -t 10 -p 'Sleeping 10 seconds. Press enter to continue.'
    clear
fi

SQUID_USER='proxy'


CACHE_DIR_SQUID='/var/spool/squid'
CACHE_DIR_SQUID_SIZE='800000'
CACHE_SWP_HIGH='95'
CACHE_SWP_LOW='90'
MEM_CACHE_MODE='always'
CACHE_MEM='1258 MB'

CLIENT_RQST_BFR_SIZE='512 KB'

DNS_V4_FIRST='on'

PORT_SQUID='3128/tcp'
PORT_PIHOLE='4711/tcp'

SVC01='dhcp'
SVC02='dhcpv6'
SVC03='dns'
SVC04='http'
SVC05='ssh'

LIB1_SQUID='/usr/lib/squid3/basic_ncsa_auth'
LIB2_SQUID='/usr/lib/squid/basic_ncsa_auth'

SERVER_IP='192.168.1.40'

MIN_OBJ_SIZE='0 KB'
MAX_OBJ_SIZE='10 GB'
MAX_OBJ_SIZE_MEM='1024 KB'

SQUID_CONF='/etc/squid/squid.conf'
SQUID_PASSWD='/etc/squid/passwd'
SQUID_WHITELIST='/etc/squid/sites.whitelist'
SQUID_BLACKLIST='/etc/squid/sites.blacklist'

DETECT_BROKEN_PCONN='off'

if [ -f "$LIB1_SQUID" ]; then BASIC_NCSA_AUTH="$LIB1_SQUID"
elif [ -f "$LIB2_SQUID" ]; then BASIC_NCSA_AUTH="$LIB2_SQUID"
else
    clear
    echo -e "File error: 'basic_ncsa_auth' was not found. Unable to set the required variable BASIC_NCSA_AUTH\\nPlease Fix...\\n"
    read -p 'Press enter to exit.'
    exit 1
fi

cat > "$SQUID_CONF" <<EOF && echo -e "squid.conf was created successfully!" || echo -e "squid.conf failed to create!"








dns_v4_first $DNS_V4_FIRST






















































acl SSL_ports port 443









http_access allow !Safe_ports

http_access allow !SSL_ports

http_access allow localhost manager
http_access deny manager

http_access deny to_localhost

include /etc/squid/conf.d/*


auth_param basic program $BASIC_NCSA_AUTH $SQUID_PASSWD
auth_param basic children 5
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
acl auth_users proxy_auth REQUIRED

http_access allow localnet
http_access allow localhost
http_access allow authenticated
http_access allow whitelist
http_access deny blocked_sites

http_access deny all

client_request_buffer_max_size $CLIENT_RQST_BFR_SIZE

dns_nameservers $SERVER_IP

minimum_object_size $MIN_OBJ_SIZE
maximum_object_size $MAX_OBJ_SIZE
maximum_object_size_in_memory $MAX_OBJ_SIZE_MEM

cache_swap_low $CACHE_SWP_LOW
cache_swap_high $CACHE_SWP_HIGH

memory_cache_mode $MEM_CACHE_MODE

cache_dir ufs $CACHE_DIR_SQUID $CACHE_DIR_SQUID_SIZE 16 256

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

cache_mem $CACHE_MEM

http_port $PORT_SQUID::4

visible_hostname debian-bullseye

detect_broken_pconn $DETECT_BROKEN_PCONN

cache_effective_user $SQUID_USER

http_accel_surrogate_remote on
esi_parser expat





















































































coredump_dir /var/spool/squid




























































































umask 022





















































































































































































EOF

if [ ! -f "$SQUID_WHITELIST" ]; then touch "$SQUID_WHITELIST"; fi
cat > "$SQUID_WHITELIST" <<'EOF' && echo -e "The whitelist was created successfully!" || echo -e "The whitelist failed to create."
<replace with your own list>
site.com
www.site.com
EOF

if [ -f "$SQUID_BLACKLIST" ]; then touch "$SQUID_BLACKLIST" ;fi
cat > "$SQUID_BLACKLIST" <<'EOF' && echo -e "The blacklist was created successfully!\\n" || echo -e "The blacklist failed to create.\\n"
<replace with your own list>
.bytedance.com
.tiktok.com
.xyz
EOF

if [ ! -f "$SQUID_PASSWD" ]; then
    htpasswd -c "$SQUID_PASSWD" squid && echo -e "\\nThe squid passwd file was created successfully!" || echo -e "\\nThe squid passwd file failed to create."
    echo
    cat "$SQUID_PASSWD"
    echo
fi

echo '[1] Add firewalld rules'
echo -e "[2] Skip\\n"
read -p 'Enter a number: ' uChoice
echo
if [[ "$uChoice" == "1" ]]; then
    firewall-cmd --permanent --add-service={"$SVC01","$SVC02","$SVC03","$SVC04","$SVC05"}
    firewall-cmd --add-zone=squid-custom
    firewall-cmd --permanent --zone=squid-custom --add-interface=lo
    firewall-cmd --permanent --zone=squid-custom --add-port={"$PORT_SQUID","$PORT_PIHOLE"}
    firewall-cmd --set-default-zone=squid-custom
    firewall-cmd --reload
    echo
    read -t 10 -p 'Sleeping for 10 seconds. Press enter to skip ahead.'
    clear
else
    clear
fi

'/etc/init.d/squid' restart && echo -e "\\nSquid restarted successfully!\\n" || echo -e "\\nSquid failed to restart!\\n"
