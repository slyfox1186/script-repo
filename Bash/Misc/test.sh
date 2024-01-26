# Clear the terminal
clear

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

# Check if script is being run directly and not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check if at least one URL is provided as an argument
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <repo_url1> [<repo_url2> ...]"
        exit 1
    fi

    # Call the git_tag function with provided repository URLs
    git_tag "$@"
fi
