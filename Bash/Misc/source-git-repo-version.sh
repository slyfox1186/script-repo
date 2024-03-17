#!/usr/bin/env bash


get_latest_release_version() {
    local url="$1"
    local tags_url="$url/.git//tags"

    latest_version=$(curl -fsSL "$url" | parse_version)
    if [[ -z "$latest_version" ]]; then
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

if [[ -z "$1" ]]; then
    echo "Usage: $0 <url>"
    exit 1
fi

pass_url="$1"
get_latest_release_version "$pass_url"

echo "$latest_version"
