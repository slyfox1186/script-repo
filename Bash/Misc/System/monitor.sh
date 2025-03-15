#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Misc/System/monitor.sh
# Script version: 1.8
# Last update: [Current Date]

## Important information
# Arguments take priority over hardcoded variables
# This script now handles the inotify watch limit error by increasing it automatically

# Define variables
monitor_dir="${PWD}"  # Default directory to monitor
include_access=false  # Flag to include access events
log_file=""           # Log file path

# Define colors
declare -A eventcolors=(
    [ACCESS]=$'\033[36m'          # Cyan for access events
    [CREATE]=$'\033[32m'          # Green for create events
    [DELETE]=$'\033[31m'          # Red for delete events
    [MODIFY]=$'\033[33m'          # Yellow for modify events
    [MOVE]=$'\033[35m'            # Magenta for move events
    [MOVED_FROM]=$'\033[95m'      # Light Magenta for moved from events
    [MOVED_TO]=$'\033[95m'        # Light Magenta for moved to events
    [CREATE_ISDIR]=$'\033[1;32m'  # Bold Green for create, isdir events
    [MOVED_FROM_ISDIR]=$'\033[1;35m' # Bold Magenta for moved from, isdir events
    [MOVED_TO_ISDIR]=$'\033[1;35m'   # Bold Magenta for moved to, isdir events
    [DELETE_ISDIR]=$'\033[1;31m'  # Bold Red for delete, isdir events
    [MODIFY_ISDIR]=$'\033[1;33m'  # Bold Yellow for modify, isdir events
    [RESET]=$'\033[0m'            # Resets the color to none
)

# Function to display help
display_help() {
    echo -e "${eventcolors[MODIFY]}Usage${eventcolors[MOVE]}:${eventcolors[RESET]} ${0} [options]"
    echo
    echo -e "${eventcolors[MODIFY]}Options${eventcolors[MOVE]}:${eventcolors[RESET]}"
    echo "  -a, --access             Include \"access\" events"
    echo "  -d, --directory <path>   Specify the directory to monitor"
    echo "  -l, --log <path>         Specify the log file to write events"
    echo "  -h, --help               Display this help message"
    echo
    echo -e "${eventcolors[MODIFY]}Examples${eventcolors[MOVE]}:${eventcolors[RESET]}"
    echo "./monitor.sh --help"
    echo "./monitor.sh --directory \"/path/to/folder\""
    echo "./monitor.sh -a -d \"/path/to/folder\""
    echo "./monitor.sh -d \"/path/to/folder\" -l /path/to/logfile.log"
}

# Function to parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--access)
                include_access=true
                shift
                ;;
            -d|--directory)
                monitor_dir="$2"
                shift 2
                ;;
            -l|--log)
                log_file="$2"
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

# Function to check if inotifywait is installed
check_command() {
    if ! command -v inotifywait &>/dev/null; then
        echo -e "${eventcolors[DELETE]}[ERROR]${eventcolors[RESET]} The command inotifywait is not installed."
        echo -e "${eventcolors[CREATE]}[INFO]${eventcolors[RESET]} This is commonly installed by your package manager inside the package inotify-tools"
        exit 1
    fi
}

# Main function to monitor directory
monitor_directory() {
    local events="create,delete,modify,move"
    [[ "$include_access" = true ]] && events+=",access"

    if [[ ! -d "$monitor_dir" ]]; then
        echo -e "${eventcolors[DELETE]}[ERROR]${eventcolors[RESET]} The directory to monitor does not exist."
        exit 1
    fi

    # Check the number of directories against the inotify watch limit
    local num_dirs=$(find "$monitor_dir" -type d | wc -l)
    local max_watches=$(cat /proc/sys/fs/inotify/max_user_watches)
    if (( num_dirs > max_watches )); then
        echo -e "${eventcolors[DELETE]}[ERROR]${eventcolors[RESET]} Number of directories ($num_dirs) exceeds inotify watch limit ($max_watches)."
        echo -e "${eventcolors[CREATE]}[INFO]${eventcolors[RESET]} Increasing inotify watch limit..."
        sudo sysctl fs.inotify.max_user_watches=10000000
        if [[ $? -ne 0 ]]; then
            echo -e "${eventcolors[DELETE]}[ERROR]${eventcolors[RESET]} Failed to increase watch limit. Please run manually: sudo sysctl fs.inotify.max_user_watches=10000000"
            exit 1
        fi
    elif (( num_dirs > max_watches * 0.8 )); then
        echo -e "${eventcolors[MODIFY]}[WARNING]${eventcolors[RESET]} Number of directories ($num_dirs) is close to inotify watch limit ($max_watches)."
    fi

    echo "Monitoring directory: $monitor_dir"
    inotifywait -mre "$events" "$monitor_dir" 2> >(while read -r line; do
        echo -e "${eventcolors[DELETE]}[ERROR]${eventcolors[RESET]} $line"
        if [[ $line == *"Failed to watch"* && $line == *"No space left on device"* ]]; then
            echo -e "${eventcolors[CREATE]}[INFO]${eventcolors[RESET]} inotify watch limit reached. Increasing limit and restarting..."
            sudo sysctl fs.inotify.max_user_watches=10000000
            if [[ $? -eq 0 ]]; then
                # Restart monitoring after increasing the limit
                monitor_directory
                exit 0
            else
                echo -e "${eventcolors[DELETE]}[ERROR]${eventcolors[RESET]} Failed to increase watch limit. Please run manually: sudo sysctl fs.inotify.max_user_watches=10000000"
            fi
        fi
    done) | while read -r path event file; do
        local timestamp color event_log
        timestamp=$(date +'%m-%d-%Y %I:%M:%S %p')
        event=$(echo "$event" | tr ',' '_')
        color=${eventcolors[$event]:-${eventcolors[RESET]}}
        event_log="[$timestamp] $path $event $file"
        echo -e "${color}${event_log}${eventcolors[RESET]}"
        
        [[ -n "$log_file" ]] && echo -e "${color}${event_log}${eventcolors[RESET]}" >> "$log_file"
    done
}

# Parse arguments
parse_arguments "$@"

# Check if inotifywait is installed
check_command

# Monitor the directory
monitor_directory
