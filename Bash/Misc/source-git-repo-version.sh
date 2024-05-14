#!/usr/bin/env bash

# This script will return the latest release version of a GitHub repository.
# Example usage: ./source-git-repo-version.sh "https://github.com/rust-lang/rust.git"

# Regex patterns
first_match='href="[^"]*/tag/\K[^"]*'
second_match='(?:[a-z-]+-)?\K([0-9]+(?:[._-][0-9]+)*(?:-[a-zA-Z0-9]+)?)'
exclude_words='alpha|beta|DEV|early|init|M[0-9]+|next|pending|pre|rc|tentative|^.$'
trim_this='s/-$//'

# Function to fetch and parse the latest release version
get_latest_release_version() {
    local url tags_url html_content main_content tags_content
    url="$1"
    releases_url="${url%.*}/releases"
    tags_url="${url%.*}/tags"

    # Fetch HTML content from both URLs
    main_content=$(curl -fsSL "$url")
    releases_content=$(curl -fsSL "$releases_url")
    tags_content=$(curl -fsSL "$tags_url")
    html_content="$releases_content $main_content $tags_content"

    echo "$html_content" | grep -oP "$first_match" | grep -oP "$second_match" | grep -Eiv "$exclude_words" | sort -rV | head -n1 | sed "$trim_this" | sed 's/^v//'
}

# Main script execution
[[ -z "$1" ]] && { echo "Usage: $0 <url>"; exit 1; }

get_latest_release_version "$1"
