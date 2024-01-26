#!/usr/bin/env bash

echo "Script started..."

# Function to retrieve the latest Git tag version from multiple repositories
git_tag() {
    for url in "$@"
    do
        echo "Processing $url..."
        result=$(git ls-remote --tags "$url" 2>&1)
        
        if [ -z "$result" ]; then
            echo "No data retrieved from $url"
            continue
        fi

        latest_tag=$(echo "$result" | \
        awk -F/ '/[0-9]+[0-9_.]+[0-9_.]*$/ {print $NF}' | \
        grep -Eo '[0-9.\_]+' | \
        sort -V | \
        tail -n1)

        # Replace underscores with dots
        latest_tag=${latest_tag//_/\.}
        
        echo "Latest tag for $url: $latest_tag"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <repo_url1> [<repo_url2> ...]"
        exit 1
    fi

    git_tag "$@"
fi
