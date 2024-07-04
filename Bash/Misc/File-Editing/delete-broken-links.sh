#!/usr/bin/env bash

# Script to recursively scan a directory for broken soft links and delete them.

# Function to display the help menu
show_help() {
    echo "Usage: $0 [--dir|-d] directory"
    echo
    echo "Options:"
    echo "  --dir, -d    Directory to scan for broken soft links"
    echo "  --help, -h   Display this help and exit"
}

# Function to delete broken soft links
delete_broken_links() {
    local dir=$1
    local broken_links=0
    
    # Find and delete broken soft links
    while IFS= read -r -d '' link; do
        if [[ -e "$link" ]]; then
            echo "Error: False positive, not deleting: $link"
        else
            echo "Deleting broken link: $link"
            if rm "$link"; then
                echo "Deleted: $link"
                ((broken_links++))
            else
                echo "Error deleting: $link"
            fi
        fi
    done < <(find "$dir" -xtype l -print0 2>/dev/null)

    if [[ $broken_links -eq 0 ]]; then
        echo "No broken links found in directory: $dir"
    else
        echo "Total broken links deleted: $broken_links"
    fi
}

# Main script
main() {
    local dir=""
    
    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dir|-d)
                dir=$2
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Check if script is run as root
    if [[ "$EUID" -ne 0 ]]; then
        echo "This script must be run as root or using sudo."
        exit 1
    fi

    # Check if directory is provided
    if [[ -z "$dir" ]]; then
        echo "Error: Directory not specified."
        show_help
        exit 1
    fi

    # Check if directory exists
    if [[ ! -d "$dir" ]]; then
        echo "Error: Directory does not exist."
        exit 1
    fi

    # Delete broken soft links
    delete_broken_links "$dir"
}

# Call the main function
main "$@"
