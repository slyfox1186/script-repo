#!/usr/bin/env bash

display_help() {
    echo "Usage: $0 [OPTIONS] PATTERN"
    echo "Search for files and directories using the locate command."
    echo "Options:"
    echo "  -c, --count       Display only the count of matching entries"
    echo "  -d, --dir         Limit results to directories only"
    echo "  -f, --file        Limit results to files only"
    echo "  -a, --all         Include both directories and files (default)"
    echo "  -C, --case        Enable case-sensitive search"
    echo "  -l, --limit       Limit the number of search results (default: 25)"
    echo "  -p, --path        Specify the path to limit the search"
    echo "  -r, --regex       Interpret the pattern as a regular expression"
    echo "  -e, --exclude     Exclude patterns from search results"
    echo "  -u, --update      Update the locate database before searching"
    echo "  -h, --help        Display this help information"
    echo "Example:"
    echo "  $0 -l 10 \"*.txt\""
    echo "  Search for files ending with .txt and limit results to 10"
}

# Initialize default values
count_only=false
directories_only=false
files_only=false
case_sensitive=false
limit=25
use_regex=false
update_db=false
search_path=""

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--count) count_only=true ;;
        -d|--dir) directories_only=true ;;
        -f|--file) files_only=true ;;
        -a|--all) directories_only=true; files_only=true ;;
        -C|--case) case_sensitive=true ;;
        -l|--limit) limit="$2"; shift ;;
        -p|--path) search_path="$2"; shift ;;
        -r|--regex) use_regex=true ;;
        -e|--exclude) exclude_patterns="$2"; shift ;;
        -u|--update) update_db=true ;;
        -h|--help) display_help; exit 0 ;;
        *) break ;;
    esac
    shift
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

if [[ $# -eq 0 ]]; then
    printf "\n%s\n" "Error: Please provide at least one search pattern."
    display_help
    exit 1
fi

search_patterns=("$@")

locate_cmd="locate"
[[ $case_sensitive != true ]] && locate_cmd+=" -i"
[[ $use_regex == true ]] && locate_cmd+=" --regex"

# Add the limit option here
[[ -n "$limit" ]] && set_limit="head -n$limit"

# Move the --null option after --limit
locate_cmd+=" --null"

# Adjusting the locate command to filter by path if provided
[[ -n "$search_path" ]] && locate_cmd+=" | grep -F \"$search_path\""

post_process_cmd=""

# Exclude patterns from search results
if [[ -n $exclude_patterns ]]; then
    exclude_cmd=" | grep -v \"$exclude_patterns\""
fi

if [[ $directories_only == true ]] && [[ $files_only == false ]]; then
    post_process_cmd=" | xargs -0 -I{} find \"{}\" -type d "$exclude_cmd" | $set_limit"
elif [[ $directories_only == false ]] && [[ $files_only == true ]]; then
    post_process_cmd=" | xargs -0 -I{} find \"{}\" -type f "$exclude_cmd" | $set_limit"
elif [[ $directories_only == true ]] && [[ $files_only == true ]]; then
    post_process_cmd=" | xargs -0 -I{} find \"{}\" "$exclude_cmd" | $set_limit"
fi

for pattern in "${search_patterns[@]}"; do
    echo "Search results for pattern: $pattern"
    echo "--------"
    full_command="${locate_cmd} \"$pattern\"${post_process_cmd}"
    if [[ -n "$full_command" ]]; then
        if ! eval "$full_command | tr '\n' '\0' | xargs -0 -n1 echo"; then
            printf "\s%s\n" "No matches found"
        fi
    fi
    echo
done
