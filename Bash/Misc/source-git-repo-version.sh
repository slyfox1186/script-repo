#!/usr/bin/env bash

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

# Function to match and filter versions from a string
match_and_filter_versions() {
    local input_string="$1"
    local latest_version

    # Use awk to match the string with the provided regex and print the last field
    latest_version=$(echo "$input_string" | awk -F/ 'match($0, /[0-9]+(\.[0-9]+)+(-[0-9]+)?/) {print substr($0, RSTART, RLENGTH)}')

    echo "$latest_version"
}

# Check if a URL is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <repo_url>"
    exit 1
fi

repo_url="$1"
latest_tag="$(get_latest_git_tag "$repo_url")"

# Correct the tag format by replacing underscores with dots
corrected_tag="${latest_tag//_/.}"
echo "Latest Git Tag: $corrected_tag"

# Example input string
input_string='href="/ImageMagick/ImageMagick/releases/tag/7.1.1-27"'

# Extract and correct the version from the input string
latest_version="$(match_and_filter_versions "$input_string")"
echo "Latest Version from Input String: $latest_version"

# Echo both values at the end
echo "$latest_version $corrected_tag"
