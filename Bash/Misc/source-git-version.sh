#!/usr/bin/env bash

# Clear the terminal
clear

# Function to retrieve the latest Git tag version from a repository
get_latest_git_tag() {
    local url="$1"
    local tag_version

    # Extracting the version number using a regular expression
    tag_version=$(git ls-remote --tags "$url" | awk -F/ '{print $NF}' | grep -Eo '([0-9]+[-_])+[0-9]+' | sort -V | tail -n1)

    # Replace underscores with dots in the version number
    tag_version=${tag_version//_/.}
    
    echo "$tag_version"
}

# Check if a URL is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <repo_url>"
    exit 1
fi

repo_url="$1"
latest_tag="$(get_latest_git_tag "$repo_url")"

# Return the latest tag to the caller script
echo "$latest_tag"
