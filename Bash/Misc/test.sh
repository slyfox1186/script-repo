#!/usr/bin/env bash

# Function to retrieve the latest Git tag version from multiple repositories
git_tag() {
    for url in "$@"
    do
        result=$(git ls-remote --tags "$url" | \
        awk -F/ '/[0-9]+[0-9_.]+[0-9_.]*$/ {print $NF}' | \
        grep -Eo '[0-9.\_]+' | \
        sort -V | \
        tail -n1)
        
        # Replace underscores with dots
        result=${result//_/\.}
        
        echo "$result"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <repo_url1> [<repo_url2> ...]"
        exit 1
    fi

    git_tag "$@"
fi
