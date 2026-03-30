#!/usr/bin/env bash

set -euo pipefail

display_help() {
    cat <<EOF
Usage: $0 [OPTIONS] PATTERN
Search for files and directories using the locate command.

Options:
  -c, --count       Display only the count of matching entries
  -d, --dir         Limit results to directories only
  -f, --file        Limit results to files only
  -a, --all         Include both directories and files (default)
  -C, --case        Enable case-sensitive search
  -l, --limit NUM   Limit the number of search results (default: 25)
  -p, --path PATH   Specify the path to limit the search
  -r, --regex       Interpret the pattern as a regular expression
  -e, --exclude PAT Exclude patterns from search results
  -u, --update      Update the locate database before searching
  -h, --help        Display this help information

Example:
  $0 -l 10 "*.txt"
EOF
}

count_only=false
directories_only=false
files_only=false
case_sensitive=false
limit=25
use_regex=false
update_db=false
search_path=""
exclude_patterns=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--count) count_only=true ;;
        -d|--dir) directories_only=true ;;
        -f|--file) files_only=true ;;
        -a|--all) directories_only=false; files_only=false ;;
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

if [[ $update_db == true ]]; then
    echo "Updating locate database..."
    if sudo updatedb; then
        echo "The database was successfully updated."
    else
        echo "Error: Failed to update locate database." >&2
        exit 1
    fi
fi

if [[ $# -eq 0 ]]; then
    echo "Error: Please provide at least one search pattern." >&2
    display_help
    exit 1
fi

for pattern in "$@"; do
    echo "Search results for pattern: $pattern"
    echo "--------"

    # Build locate arguments as an array
    locate_args=()
    [[ $case_sensitive != true ]] && locate_args+=(-i)
    [[ $use_regex == true ]] && locate_args+=(--regex)
    locate_args+=("$pattern")

    # Run locate and filter results
    found=0
    while IFS= read -r result; do
        # Filter by path if specified
        if [[ -n "$search_path" ]] && [[ "$result" != *"$search_path"* ]]; then
            continue
        fi

        # Filter by exclude pattern
        if [[ -n "$exclude_patterns" ]] && [[ "$result" == *"$exclude_patterns"* ]]; then
            continue
        fi

        # Filter by type
        if [[ $directories_only == true ]] && [[ ! -d "$result" ]]; then
            continue
        fi
        if [[ $files_only == true ]] && [[ ! -f "$result" ]]; then
            continue
        fi

        if [[ $count_only == true ]]; then
            ((found++))
            continue
        fi

        echo "$result"
        ((found++))

        if [[ $found -ge $limit ]]; then
            break
        fi
    done < <(locate "${locate_args[@]}" 2>/dev/null || true)

    if [[ $count_only == true ]]; then
        echo "Count: $found"
    elif [[ $found -eq 0 ]]; then
        echo "No matches found"
    fi
    echo
done
