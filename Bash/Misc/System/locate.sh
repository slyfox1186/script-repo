#!/bin/bash

# Function to display help information
display_help() {
    echo "Usage: $0 [OPTIONS] PATTERN"
    echo "Search for files and directories using the locate command."
    echo
    echo "Options:"
    echo "    -c, --count       Display only the count of matching entries"
    echo "    -d, --dir         Limit results to directories only"
    echo "    -f, --file        Limit results to files only"
    echo "    -a, --all         Include both directories and files (default)"
    echo "    -i, --ignore-case Ignore case distinctions in the pattern"
    echo "    -l, --limit       Limit the number of search results (default: 20)"
    echo "    -r, --regex       Interpret the pattern as a regular expression"
    echo "    -u, --update      Update the locate database before searching"
    echo "    -h, --help        Display this help information"
    echo
    echo "Example:"
    echo "    $0 -i -l 10 \"*.txt\""
    echo "    Search for files ending with .txt (case-insensitive) and limit results to 10"
}

# Default values for options
count_only=false
directories_only=false
files_only=false
ignore_case=false
limit=20
use_regex=false
update_db=false

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--count)
            count_only=true
            shift
            ;;
        -d|--dir)
            directories_only=true
            shift
            ;;
        -f|--file)
            files_only=true
            shift
            ;;
        -a|--all)
            directories_only=false
            files_only=false
            shift
            ;;
        -i|--ignore-case)
            ignore_case=true
            shift
            ;;
        -l|--limit)
            limit="$2"
            shift 2
            ;;
        -r|--regex)
            use_regex=true
            shift
            ;;
        -u|--update)
            update_db=true
            shift
            ;;
        -h|--help)
            display_help
            exit 0
            ;;
        -*)
            echo "Invalid option: $1" >&2
            display_help >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Update the locate database if requested
if [[ $update_db == true ]]; then
    echo "Updating locate database..."
    if ! sudo updatedb; then
        printf "\n%s\n" "Error: Failed to update locate database." >&2
        exit 1
    else
        printf "\n%s\n" "The datebase was successfully updated."
        exit 0
    fi
fi

# Check if search patterns are provided
if [[ $# -eq 0 ]]; then
    echo "Error: Please provide at least one search pattern." >&2
    display_help >&2
    exit 1
fi

search_patterns=("$@")

# Build the locate command with options
locate_cmd="locate"
if [[ $ignore_case == true ]]; then
    locate_cmd+=" -i"
fi
if [[ $use_regex == true ]]; then
    locate_cmd+=" --regex"
fi
locate_cmd+=" --limit $limit"

# Determine search type (directories, files, or both)
if [[ $directories_only == true ]]; then
    post_process_cmd=" | xargs -I {} find {} -maxdepth 0 -type d"
elif [[ $files_only == true ]]; then
    post_process_cmd=" | xargs -I {} find {} -maxdepth 0 -type f"
else
    post_process_cmd=""
fi

# Execute the locate command and process the results
if [[ $count_only == true ]]; then
    count=0
    for pattern in "${search_patterns[@]}"; do
        count=$((count + $(eval "$locate_cmd \"$pattern\" $post_process_cmd | wc -l")))
    done
    echo "Total number of matching entries: $count"
else
    for pattern in "${search_patterns[@]}"; do
        echo "Search results for pattern: $pattern"
        eval "$locate_cmd \"$pattern\" $post_process_cmd | tr '\n' '\0' | xargs -0 -n 1 echo"
        echo "-----"
    done
fi
