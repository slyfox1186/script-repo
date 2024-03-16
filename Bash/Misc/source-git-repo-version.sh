#!/usr/bin/env bash

# Updated: 03.03.2024
# Improved the RegEx parsing which has allowed more results

# Function to retrieve the latest Git tag version from a repository
get_latest_release_version() {
    local url="$1"
    local tags_url="${url/.git/}/tags"

    # Try fetching from the original URL
    latest_version=$(curl -fsSL "$url" | parse_version)
    if [[ -z "$latest_version" ]]; then
        # If no version found, try the alternative URL
        latest_version=$(curl -fsSL "$tags_url" | parse_version)
    fi
}

parse_version() {
    grep -oP 'href="[^"]*\/[a-z]*\/tag(s)?([a-z\/]*)\/[a-z\.\-]*[0-9][0-9\.\_]+[a-zA-Z0-9\.\-]*"' |
    grep -oP '[0-9][0-9\.\_]+[a-zA-Z0-9\.\-]*' |
    grep -Eiv 'alpha|beta|init|next|pre|rc|tentative' |
    grep -oP '([0-9\.]*)\.[0-9]+[0-9\-]*' | 
    sort -rV |
    head -n1 |
    sed 's/\-$//'
}

# Check if a URL is provided as an url
if [ -z "$1" ]; then
    echo "Usage: $0 <url>"
    exit 1
fi

pass_url="$1"
get_latest_release_version "$pass_url"

echo "$latest_version"
