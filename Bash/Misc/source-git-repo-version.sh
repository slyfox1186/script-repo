#!/usr/bin/env bash

# Function to retrieve the latest Git tag version from a repository
find_latest_git_tag() {
    local url="$1"
    local tags_url="${url/.git/}/tags"
    local tag_version

    # Try fetching from the original URL
    tag_version=$(curl -sSL "$url" | parse_version)
    if [[ -z "$tag_version" ]]; then
        # If no version found, try the alternative URL
        tag_version=$(curl -sSL "$tags_url" | parse_version)
    fi

    echo "$tag_version"
}

parse_version() {
    grep -Eo 'href="[^"]*\/tag\/[a-z\.\-]*[0-9][0-9\.\_]+[a-zA-Z0-9\.\-]*"' |
    grep -Eo '[0-9][0-9\.\_]+[a-zA-Z0-9\.\-]*' |
    grep -Eiv 'alpha|beta|pre|rc|tentative' |
    sort -rV |
    head -n1
}

# Check if a URL is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <repo_url>"
    exit 1
fi

repo_url="$1"
latest_tag="$(find_latest_git_tag "$repo_url")"

echo "$latest_tag"
