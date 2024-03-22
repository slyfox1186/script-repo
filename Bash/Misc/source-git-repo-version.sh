#!/usr/bin/env bash

# Set variables
first_match='href="[^"]*/[a-z]*/tag(s)?([a-z/]*)/[a-z.-]*[0-9][0-9._]+[a-zA-Z0-9.-]*"'
second_match='[0-9][0-9._]+[a-zA-Z0-9.-]*'
third_match='([0-9.]*).[0-9]+[0-9-]*'
exclude_words='alpha|beta|early|init|next|pending|pre|rc|tentative'
trim_this='s/-$//'

# Send the RegEx pattern to cURL
get_latest_release_version() {
    local url="$1"
    local tags_url="$url/tags"

    latest_version=$(curl -fsSL "$url" | parse_version)
    [[ -z "$latest_version" ]] && latest_version=$(curl -fsSL "$tags_url" | parse_version)
}

# Create RegEx strings to return the latest release version of the targeted GitHub repository
parse_version() {
    grep -oP "$first_match" |
    grep -oP "$second_match" |
    grep -Eiv "$exclude_words" |
    grep -oP "$third_match" |
    sort -rV |
    head -n1 |
    sed "$trim_this"
}

# Exit the script if a first argument was not passed to the script
# (This should be the git URL of the desired repository)
if [[ -z "$1" ]]; then
    echo "Usage: $0 <url>"
    exit 1
fi

# Pass the first argument to cURL and RegEx
get_latest_release_version "$1"

echo "$latest_version"
