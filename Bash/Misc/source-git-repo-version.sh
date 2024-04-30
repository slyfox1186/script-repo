#!/usr/bin/env bash

# This script will return the latest release version of a GitHub repository.
# Example usage: ./source-git-repo-version.sh "https://github.com/rust-lang/rust.git"
# Expected Output: e.g., 1.77.2

# Regex patterns
first_match='href="[^"]*/releases/tag/\K[^"]*'
second_match='(?:[a-z-]+-)?\K([0-9]+(?:[._-][0-9]+)*(?:-[a-zA-Z0-9]+)?)'
exclude_words='alpha|beta|early|init|M2|next|pending|pre|rc|tentative|^.$'
trim_this='s/-$//'

# Function to fetch and parse the latest release version
get_latest_release_version() {
    local url="$1"
    local tags_url="${url%.*}/tags"  # Adjust the URL to point to the tags page

    # Correct usage of the pipe with curl and grep commands
    latest_version=$(curl -fsSL "$url" | parse_version)
    [[ -z "$latest_version" ]] && latest_version=$(curl -fsSL "$tags_url" | parse_version)
    echo "$latest_version"
}

# Parse the version from HTML content
parse_version() {
    grep -oP "$first_match" |
    grep -oP "$second_match" |
    grep -Eiv "$exclude_words" |
    sort -rV | head -n1 |
    sed "$trim_this" | sed 's/^v//'
}

# Main script execution
if [[ -z "$1" ]]; then
    echo "Usage: $0 <url>"
    exit 1
fi

version=$(get_latest_release_version "$1")
echo "$version"
