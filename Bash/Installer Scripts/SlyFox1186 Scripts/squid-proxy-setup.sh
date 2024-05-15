#!/usr/bin/env bash

set -euo pipefail

configure_squid_user_and_directories() {
    log "Creating Squid user and directories..."
    sudo useradd -M -r -U -d /var/cache/squid -s /usr/sbin/nologin proxy
    sudo mkdir -p /var/cache/squid /var/log/squid
    sudo chown -R proxy:proxy /var/cache/squid /var/log/squid || fail "Failed to create Squid user and directories"
}

parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -c|--cache-size) CACHE_SIZE_GB="$2"; shift ;;
            -e|--email) EMAIL="$2"; shift ;;
            -d|--ddns-service) DDNS_SERVICE="$2"; shift ;;
            -H|--ddns-hostname) DDNS_HOSTNAME="$2"; shift ;;
            -u|--ddns-username) DDNS_USERNAME="$2"; shift ;;
            -p|--ddns-password) DDNS_PASSWORD="$2"; shift ;;
            -P|--parental-control) PARENTAL_CONTROL=true ;;
            -a|--no-ad-blocker) AD_BLOCKER=false ;;
            -s|--ssl-bump) ENABLE_SSL_BUMP=true ;;
            -h|--help) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
        shift
    done
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]
Set up a home Squid proxy server with various features like caching, parental controls, ad blocking, SSL bumping, and more.

Options:
  -c, --cache-size SIZE          Set the cache directory size in GB (default: 50)
  -e, --email EMAIL              Email address to send notifications to
  -d, --ddns-service SERVICE     Dynamic DNS service provider (e.g., noip, duckdns, dynu)
  -H, --ddns-hostname HOSTNAME   Dynamic DNS hostname
  -u, --ddns-username USERNAME   Dynamic DNS username
  -p, --ddns-password PASSWORD   Dynamic DNS password
  -P, --parental-control         Enable parental control (block adult content)
  -a, --no-ad-blocker            Disable ad blocker
  -s, --ssl-bump                 Enable SSL bumping
  -h, --help                     Display this help menu

Examples:
  $0 --cache-size 100 --email user@example.com --ddns-service noip --ddns-hostname myproxy.ddns.net --ddns-username myuser --ddns-password mypass --parental-control --no-ad-blocker --ssl-bump
EOF
    exit 1
}

main() {
    parse_arguments "$@"
    configure_squid_user_and_directories

    # Configure Squid options based on arguments
    if [[ -n "$CACHE_SIZE_GB" ]]; then
        sed -i "s/cache_dir ufs \/var\/spool\/squid.*/cache_dir ufs \/var\/spool\/squid $((CACHE_SIZE_GB * 1024)) 16 256/g" /etc/squid/squid.conf
    fi

    if $PARENTAL_CONTROL; then
        cat "$SQUID_BLACKLIST" >> /etc/squid/blacklist
    fi

    if ! $AD_BLOCKER; then
        sed -i '/^acl ads/d' /etc/squid/squid.conf
        sed -i '/^http_access deny ads/d' /etc/squid/squid.conf
    fi

    if $ENABLE_SSL_BUMP; then
        apt -y install ssl-cert
        {
            ssl_bump server-first all
            sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/lib/ssl_db -M 4MB
            sslcrtd_children
        } >> /etc/squid/squid.conf
    fi

    # Restart and enable Squid service
    systemctl restart squid
    systemctl enable squid

    log "Squid installation completed successfully!"
}

# Default values
CACHE_SIZE_GB=50
EMAIL=""
DDNS_SERVICE=""
DDNS_HOSTNAME=""
DDNS_USERNAME=""
DDNS_PASSWORD=""
PARENTAL_CONTROL=false
AD_BLOCKER=true
ENABLE_SSL_BUMP=false

# Blacklist file
SQUID_BLACKLIST="/etc/squid/blacklist"

main "$@"
