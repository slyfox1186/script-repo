#!/usr/bin/env bash

# Check if a URL is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <repo_url>"
    exit 1
fi

# Function to retrieve the latest Git tag version from a repository
get_latest_git_tag() {
    local url="$1"
    local tag_version

    # Fetch the latest tag version, sort, and keep the last one
    tag_version=$(git ls-remote --tags "$url" | \
                  awk -F/ '/[0-9]+[0-9_.]+[0-9_.]*$/ {print $NF}' | \
                  grep -Eo '[0-9._]+' | \
                  sort -V | \
                  tail -n1)
    
    echo "$tag_version"
}

# Call the function with the provided GitHub repo URL as an argument
latest_tag="$(get_latest_git_tag "$1")"

# Correct the tag format by replacing underscores with dots
corrected_tag="${latest_tag//_/.}"

# Output the latest tag version
echo "$latest_tag $corrected_tag"
