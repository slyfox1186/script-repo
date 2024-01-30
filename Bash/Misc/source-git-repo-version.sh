#!/usr/bin/env bash

# Function to retrieve the latest Git tag version from a repository
get_latest_git_tag() {
    local url="$1"
    local tag_version

    # Fetch the latest tag version, sort, and keep the last one
    tag_version=$(git ls-remote --tags "$url" | \
                  awk -F'/' '{print $NF}' | \
                  grep -Eo '[0-9]+[-_\.]*[0-9]+([-_\.]*[0-9]+)*' | \
                  sort -V | \
                  tail -n1)
    
    # Format the version by replacing underscores and possible preceding characters with dots
    formatted_version=$(echo "$tag_version" | sed 's/[^0-9]*\([0-9]\+\)[-_]\?\([0-9]\+\)[-_]\?\([0-9]\+\).*/\1.\2.\3/')

    echo "$formatted_version"
}

# Check if a URL is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <repo_url>"
    exit 1
fi

repo_url="$1"
latest_tag="$(get_latest_git_tag "$repo_url")"

echo "$latest_tag"
