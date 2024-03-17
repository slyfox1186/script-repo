#!/bin/bash

container_name='pihole-unbound'

wl_fname='lista.txt'

if [ ! -f "$wl_fname" ]; then
    echo "File $wl_fname not found!"
    exit 1
fi

dos2unix $wl_fname

while IFS= read -r url; do
    trimmed_url=$(echo "$url" | xargs)
    domain=$(echo "$trimmed_url" | awk -F/ '{print $3}')
    if [ -n "$domain" ]; then
        echo "Adding domain: $domain to the whitelist"
        docker exec "$container_name" pihole -w "$domain"
    fi
done < "$wl_fname"

echo "All domains have been added to the whitelist."
