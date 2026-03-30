#!/usr/bin/env bash

set -euo pipefail

read -rp "Enter your GitHub username: " username

if [[ -z "$username" ]]; then
    echo "Error: Username cannot be empty."
    exit 1
fi

github_dir="$HOME/GitHub"
mkdir -p "$github_dir"
cd "$github_dir" || exit 1

echo "Fetching repository list for '$username'..."

page=1
repos=()
while true; do
    response=$(curl -fsS "https://api.github.com/users/$username/repos?per_page=100&page=$page") || {
        echo "Error: Failed to fetch repos. Check your username and network connection."
        exit 1
    }

    # Extract clone URLs; break when page returns empty array
    page_repos=$(echo "$response" | grep -o '"clone_url": *"[^"]*"' | sed 's/"clone_url": *"//;s/"$//')
    [[ -z "$page_repos" ]] && break

    while IFS= read -r url; do
        repos+=("$url")
    done <<< "$page_repos"

    ((page++))
done

if [[ ${#repos[@]} -eq 0 ]]; then
    echo "No repositories found for user '$username'."
    exit 0
fi

echo "Found ${#repos[@]} repositories."

for repo_url in "${repos[@]}"; do
    repo_name="${repo_url##*/}"
    repo_name="${repo_name%.git}"

    if [[ -d "$repo_name" ]]; then
        echo "Skipping $repo_name (already exists)"
    else
        echo "Cloning $repo_name..."
        git clone "$repo_url" || echo "Warning: Failed to clone $repo_name"
    fi
done

echo
echo "All repositories cloned to: $github_dir"
