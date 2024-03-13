#!/bin/bash

# Set the name of your Pi-hole Docker container
container_name='pihole-unbound'

# Set the name of your txt file with the domains to whitelist
wl_fname='lista.txt'

# Check if the file exists
if [ ! -f "$wl_fname" ]; then
    echo "File $wl_fname not found!"
    exit 1
fi

# Convert Windows line endings to Unix line endings
dos2unix $wl_fname

# Loop through each line in yout txt file and add it to the Pi-hole whitelist
while IFS= read -r url; do
    # Trim the URL to remove possible white spaces and extract the domain
    trimmed_url=$(echo "$url" | xargs)
    # Use awk to extract the domain from a full URL
    domain=$(echo "$trimmed_url" | awk -F/ '{print $3}')
    # Check if the domain variable is not empty
    if [ -n "$domain" ]; then
        echo "Adding domain: $domain to the whitelist"
        docker exec "$container_name" pihole -w "$domain"
    fi
done < "$wl_fname"

echo "All domains have been added to the whitelist."
