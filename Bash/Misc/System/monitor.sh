#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Misc/System/monitor.sh
# Script version: 1.3
# Last update: 05-28-24

## Important information
# Arguments take priority over hardcoded variables

# Define variables
monitor_dir="$PWD"        # Default directory to monitor
include_access=false      # Flag to include access events

# Define colors
COLOR_RESET="\033[0m"
COLOR_CREATE="\033[32m"   # Green for create events
COLOR_DELETE="\033[31m"   # Red for delete events
COLOR_MODIFY="\033[33m"   # Yellow for modify events
COLOR_MOVE="\033[35m"     # Magenta for move events
COLOR_ACCESS="\033[36m"   # Cyan for access events

# Function to display help
function display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -d, --directory    Specify the directory to monitor"
    echo "  -a, --access       Include access events"
    echo "  -h, --help         Display this help message"
}

# Function to parse arguments
function parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -d|--directory)
                monitor_dir="$2"
                shift 2
                ;;
            -a|--access)
                include_access=true
                shift
                ;;
            -h|--help)
                display_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                display_help
                exit 1
                ;;
        esac
    done
}

# Function to check if inotifywait is installed
function check_inotifywait() {
    if ! command -v inotifywait &> /dev/null; then
        echo "Error: inotifywait is not installed. This command is commonly installed by your package manager inside the package \"inotify-tools\""
        exit 1
    fi
}

# Function to get the color for an event
function get_color_for_event() {
    local event="$1"
    case "$event" in
        *CREATE*)
            echo "$COLOR_CREATE"
            ;;
        *DELETE*)
            echo "$COLOR_DELETE"
            ;;
        *MODIFY*)
            echo "$COLOR_MODIFY"
            ;;
        *MOVE*)
            echo "$COLOR_MOVE"
            ;;
        *ACCESS*)
            echo "$COLOR_ACCESS"
            ;;
        *)
            echo "$COLOR_RESET"
            ;;
    esac
}

# Main function to monitor directory
function monitor_directory() {
    local events="create,delete,modify,move"
    if [ "$include_access" = true ]; then
        events+=",access"
    fi

    echo "Monitoring directory: $monitor_dir"
    inotifywait -mre "$events" "$monitor_dir" |
    while read -r event; do
        printf -v timestamp '%(%m-%d-%Y %I:%M:%S %p)T' -1
        color=$(get_color_for_event "$event")
        echo -e "$color[$timestamp] $event$COLOR_RESET"
    done
}

# Parse arguments
parse_arguments "$@"

# Check if inotifywait is installed
check_inotifywait

# Monitor the directory
monitor_directory
