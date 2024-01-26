#!/usr/bin/env bash

# Function to retrieve the latest Git tag version from a repository
get_latest_git_tag() {
    local url="$1"
    local tag_version

    tag_version=$(git ls-remote --tags "$url" | awk -F/ '/[0-9]+\.[0-9]+[0-9\.]*$/ {print $NF}' | grep -Eo '[0-9\.]+' | sort -V | tail -n1)
    
    echo "$tag_version"
}

# Check if a URL is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <repo_url>"
    exit 1
fi

repo_url="$1"
latest_tag=$(get_latest_git_tag "$repo_url")

# Return the latest tag to the caller script
echo "$latest_tag"
