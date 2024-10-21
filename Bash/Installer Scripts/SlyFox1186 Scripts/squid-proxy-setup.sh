#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

# Variables
squid_user=squid
squid_conf="/etc/squid/squid.conf"
squid_passwords="/etc/squid/passwords"
squid_whitelist="/etc/squid/whitelist.txt"
squid_blacklist="/etc/squid/blacklist.txt"
backup_dir="/etc/squid/backup"
log_file="/var/log/squid-setup.log"
health_check_interval=60 # seconds
ssh_port=31500 # default SSH port, user can modify this
dns_servers="127.0.0.1 1.1.1.1 1.0.0.1"
max_obj_size=1
cache_mem=512
http_port=3128

# Functions

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

backup_configs() {
    echo "Backing up current Squid configuration..." | tee -a "$log_file"
    cp $squid_conf "$backup_dir/squid.conf.bak"
    cp $squid_whitelist "$backup_dir/whitelist.txt.bak"
    cp $squid_blacklist "$backup_dir/blacklist.txt.bak"
    echo "Backup completed." | tee -a "$log_file"
}

restore_configs() {
    echo "Restoring Squid configuration from backup..." | tee -a "$log_file"
    cp "$backup_dir/squid.conf.bak" $squid_conf
    cp "$backup_dir/whitelist.txt.bak" $squid_whitelist
    cp "$backup_dir/blacklist.txt.bak" $squid_blacklist
    echo "Restore completed." | tee -a "$log_file"
}

interactive_config() {
    read -p "Enter visible hostname (default: $(hostname)): " visible_hostname_input
    visible_hostname="${visible_hostname_input:-$(hostname)}"

    read -p "Enter Squid HTTP port (default: $http_port): " http_port_input
    http_port="${http_port_input:-$http_port}"

    read -p "Enter memory cache size in MB (default: $cache_mem): " cache_mem_input
    cache_mem="${cache_mem_input:-$cache_mem}"

    read -p "Enter maximum object size in MB (default: $max_obj_size): " max_obj_size_input
    max_obj_size="${max_obj_size_input:-$max_obj_size}"

    read -p "Enter DNS nameservers (default: $dns_servers): " dns_servers_input
    dns_servers="${dns_servers_input:-"$dns_servers"}"

    read -p "Enter SSH port (default: $ssh_port): " ssh_port_input
    ssh_port="${ssh_port_input:-$ssh_port}"
}

configure_squid() {
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
acl Safe_ports port 563                         # NNTP (USENET news transfer) over SSL
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

dns_nameservers $dns_servers

minimum_object_size 64 bytes
maximum_object_size $max_obj_size MB
maximum_object_size_in_memory $max_obj_size MB

cache_swap_low 90
cache_swap_high 95
cache_mem $cache_mem MB

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

http_port $http_port
visible_hostname $visible_hostname

detect_broken_pconn off
client_persistent_connections on
server_persistent_connections off
http_accel_surrogate_remote on
esi_parser expat
shutdown_lifetime 5 seconds
coredump_dir /var/spool/squid
umask 022
EOF
}

log_setup() {
    echo "$(date) - Squid setup initiated." >> "$log_file"
}

monitor_squid() {
    while true; do
        if ! systemctl is-active --quiet squid; then
            echo "Squid service is stopped!" | tee -a "$log_file"
        fi
        sleep $health_check_interval
    done &
}

install_dependencies() {
    apt -y install squid squid-common squid-langpack squid-cgi apache2-utils squidclient
}

setup_whitelist_blacklist() {
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
.facebook.com
.tiktok.com
.whatsapp.com
EOF
}

setup_passwords() {
    if [[ ! -f "$squid_passwords" ]]; then
        if ! htpasswd -c "$squid_passwords" "$squid_user"; then
            printf "\n%s\n\n" 'The squid passwd file failed to create.'
        else
            printf "\n%s\n\n" 'The squid passwd file was created successfully!'
        fi
        echo
        cat "$squid_passwords"
    fi
}

configure_firewall() {
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
            ufw allow "$ssh_port/tcp"
            ufw enable
            service ufw start
            echo
            ;;
        2)  ;;
        "") ;;
        *)  printf "%s\n\n" 'Bad user input.'
            exit 1
            ;;
    esac
}

restart_squid() {
    systemctl restart squid
    systemctl enable squid
}

enable_automatic_updates() {
    echo "[1] Enable automatic updates"
    echo "[2] Skip"
    echo
    read -p 'Enter a number: ' update_choice
    clear

    case "$update_choice" in
        1)  echo "Enabling automatic updates for Squid..."
            apt-get install unattended-upgrades
            dpkg-reconfigure --priority=low unattended-upgrades
            echo "Automatic updates enabled." | tee -a "$log_file"
            ;;
        2)  ;;
        "") ;;
        *)  printf "%s\n\n" 'Bad user input.'
            exit 1
            ;;
    esac
}

help_menu() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help                Show this help message and exit"
    echo "  -b, --backup              Backup current Squid configuration"
    echo "  -r, --restore             Restore Squid configuration from backup"
    echo "  -i, --interactive         Interactive configuration setup"
    echo "  -m, --monitor             Start Squid monitoring and alert system"
    echo "  -u, --update              Enable automatic updates for Squid"
    echo "  --maintenance             Enable maintenance mode for Squid"
}

main() {
    log_setup

    # Ensure backup directory exists
    mkdir -p "$backup_dir"

    # Ensure Squid user exists
    if getent passwd squid &>/dev/null; then
        echo "The user \"squid\" was found"
    else
        echo "The user \"squid\" was not found"
        create_squid_user
    fi

    # Setup whitelist and blacklist
    setup_whitelist_blacklist

    # Install necessary dependencies
    install_dependencies

    # Setup passwords
    setup_passwords

    # Configure firewall
    configure_firewall

    # Monitor Squid service
    monitor_squid

    # Restart Squid service
    restart_squid

    # Enable automatic updates
    enable_automatic_updates

    # Provide interactive options for configuration
    echo
    echo "[1] Backup current configuration"
    echo "[2] Restore configuration from backup"
    echo "[3] Interactive configuration"
    echo "[4] Skip"
    echo
    read -p 'Enter a number: ' config_choice
    clear

    case "$config_choice" in
        1)  backup_configs ;;
        2)  restore_configs ;;
        3)  interactive_config
            configure_squid
            restart_squid
            ;;
        4)  ;;
        "") ;;
        *)  printf "%s\n\n" 'Bad user input.'
            exit 1
            ;;
    esac
}

# Parse command-line arguments
case "$1" in
    -h|--help)
        help_menu
        ;;
    -b|--backup)
        backup_configs
        ;;
    -r|--restore)
        restore_configs
        ;;
    -i|--interactive)
        interactive_config
        configure_squid
        restart_squid
        ;;
    -m|--monitor)
        monitor_squid
        ;;
    -u|--update)
        enable_automatic_updates
        ;;
    --maintenance)
        systemctl stop squid
        ;;
    *)
        main "$@"
        ;;
esac
