#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Misc/System/monitor.sh
# Script version: 1.0
# Last update: 05-28-24

## Disclaimer
# Two sudo commands are in this script and both are used to run the APT package
# manager to install a required package if the user chooses to. Otherwise, this should
# be considered a script that does not require "root" access.

## Important information
# Arguments take priority over hardcoded variables

# Define variables
monitor_dir="/path/to/default/directory"  # Default directory to monitor
log_file="file_changes.log"  # Log file to store changes

# Define colors
COLOR_RESET="\033[0m"
COLOR_CREATE="\033[32m"   # Green for create events
COLOR_DELETE="\033[31m"   # Red for delete events
COLOR_MODIFY="\033[33m"   # Yellow for modify events
COLOR_MOVE="\033[36m"     # Cyan for move events

# Function to display help
function display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -d, --directory    Specify the directory to monitor"
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

# Function to check if inotifywait is installed and prompt for installation if not
function check_inotifywait() {
    if ! command -v inotifywait &> /dev/null; then
        echo "Error: inotifywait is not installed."
        read -p "Do you want to install it now? (yes/no) " answer
        case "$answer" in
            [Yy]* )
                sudo apt update
                sudo apt -y install inotify-tools
                if ! command -v inotifywait &>/dev/null; then
                    echo "Installation failed. Please install inotify-tools manually."
                    exit 1
                fi
                ;;
            [Nn]* )
                echo "Please install inotify-tools and run the script again."
                exit 1
                ;;
            * )
                echo "Please answer yes or no."
                exit 1
                ;;
        esac
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
        *)
            echo "$COLOR_RESET"
            ;;
    esac
}

# Main function to monitor directory
function monitor_directory() {
    echo "Monitoring directory: $monitor_dir"
    inotifywait -m -r -e modify,create,delete,move "$monitor_dir" |
    while read -r event; do
        timestamp=$(date +'%m-%d-%Y %H:%M:%S-%p')
        color=$(get_color_for_event "$event")
        echo -e "$color[$timestamp] $event$COLOR_RESET" | tee -a "$log_file"
    done
}

# Parse arguments
parse_arguments "$@"

# Check if inotifywait is installed
check_inotifywait

# Monitor the directory
monitor_directory
