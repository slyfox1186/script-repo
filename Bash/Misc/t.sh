#!/usr/bin/env bash

echo "Script started..."

# Function to retrieve the latest Git tag version from multiple repositories
git_tag() {
    for url in "$@"
    do
        echo "Processing $url..."
        tags=$(git ls-remote --tags "$url" 2>&1)

        if [ $? -ne 0 ]; then
            echo "Error fetching tags from $url: $tags"
            continue
        fi

        if [ -z "$tags" ]; then
            echo "No tags found for $url"
            continue
        fi

        latest_tag=$(echo "$tags" | \
        awk -F/ '/[0-9]+[0-9_.]+[0-9_.]*$/ {print $NF}' | \
        grep -Eo '[0-9.\_]+' | \
        sort -V | \
        tail -n1)

        if [ -z "$latest_tag" ]; then
            echo "No version tag found for $url"
        else
            # Replace underscores with dots
            latest_tag=${latest_tag//_/\.}
            echo "Latest tag for $url: $latest_tag"
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <repo_url1> [<repo_url2> ...]"
        exit 1
    fi

    git_tag "$@"
fi
