#!/usr/bin/env bash

# Set the GitHub username
read -p "Enter your GitHub username: " username
username="$username"

# Set the target directory
github_dir="$HOME/GitHub"

# Create the target directory if it doesn't exist
mkdir -p "$github_dir"

# Change to the target directory
cd "$github_dir" || exit 1

# Get the list of repositories for the user
repos=$(curl -fsS "https://api.github.com/users/$username/repos?per_page=1000" | grep -o 'https://github.com/[^"]*')

# Clone each repository
for repo in "$repos"; do
    repo_name=$(echo "$repo" | cut -d'/' -f2 | cut -d'.' -f1)
    if [[ ! -d "$repo_name" ]]; then
        git clone "$repo"
    else
        echo
        echo "Skipping $repo_name (already exists)"
    fi
done

echo
echo "All repositories cloned successfully to: $github_dir"
