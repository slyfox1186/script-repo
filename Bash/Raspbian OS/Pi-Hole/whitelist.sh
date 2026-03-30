#!/usr/bin/env bash

set -euo pipefail

container_name="${1:-pihole-unbound}"
wl_fname="${2:-lista.txt}"

if [[ ! -f "$wl_fname" ]]; then
    echo "Error: File '$wl_fname' not found."
    echo "Usage: $0 [container_name] [whitelist_file]"
    exit 1
fi

if ! command -v dos2unix &>/dev/null; then
    echo "Error: dos2unix is not installed."
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
    echo "Error: Docker container '$container_name' is not running."
    exit 1
fi

dos2unix "$wl_fname"

count=0
while IFS= read -r url; do
    # Trim whitespace
    url="${url#"${url%%[![:space:]]*}"}"
    url="${url%"${url##*[![:space:]]}"}"

    [[ -z "$url" || "$url" == \#* ]] && continue

    # Extract domain from URL (strip protocol and path)
    domain="${url#*://}"
    domain="${domain%%/*}"

    if [[ -n "$domain" ]]; then
        echo "Adding domain: $domain"
        docker exec "$container_name" pihole -w "$domain"
        ((count++))
    fi
done < "$wl_fname"

echo "Done. Added $count domain(s) to the whitelist."
