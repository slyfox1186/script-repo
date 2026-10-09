#!/usr/bin/env bash
# Script to recursively scan multiple directories for broken soft links and delete them.

# Function to display the help menu
show_help() {
    echo "Usage: $0 [--dir|-d] directory1 [directory2 ...]"
    echo
    echo "Options:"
    echo "  --dir, -d    Directories to scan for broken soft links"
    echo "  --help, -h   Display this help and exit"
}

# Function to delete broken soft links
delete_broken_links() {
    local dir=$1
    local broken_links=0
    
    echo "Processing directory: $dir"
    
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
        echo "Total broken links deleted in $dir: $broken_links"
    fi
    echo
}

# Main script
main() {
    local dirs=()
    
    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dir|-d)
                shift
                while [[ "$#" -gt 0 && ! "$1" =~ ^--.* ]]; do
                    dirs+=("$1")
                    shift
                done
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

    # Check if directories are provided
    if [[ ${#dirs[@]} -eq 0 ]]; then
        echo "Error: No directories specified."
        show_help
        exit 1
    fi

    # Process each directory
    for dir in "${dirs[@]}"; do
        # Check if directory exists
        if [[ ! -d "$dir" ]]; then
            echo "Error: Directory does not exist: $dir"
            continue
        fi

        # Delete broken soft links
        delete_broken_links "$dir"
    done
}

# Call the main function
main "$@"
