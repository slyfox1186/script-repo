#!/usr/bin/env bash

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Misc/System/monitor.sh
# Script version: 1.6
# Last update: 05-29-24

## Important information
# Arguments take priority over hardcoded variables

# Define variables
monitor_dir="${PWD}"  # Default directory to monitor
include_access=false  # Flag to include access events
log_file=""           # Log file path

# Define colors
declare -A eventcolors=(
    [ACCESS]=$'\033[36m'   # Cyan for access events
    [CREATE]=$'\033[32m'   # Green for create events
    [DELETE]=$'\033[31m'   # Red for delete events
    [MODIFY]=$'\033[33m'   # Yellow for modify events
    [MOVE]=$'\033[35m'     # Magenta for move events
    [RESET]=$'\033[0m'     # Resets the color to none
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
    while [[ "${#}" -gt 0 ]]; do
        case "${1}" in
            -a|--access)
                include_access=true
                shift
                ;;
            -d|--directory)
                monitor_dir="${2}"
                shift 2
                ;;
            -l|--log)
                log_file="${2}"
                shift 2
                ;;
            -h|--help)
                display_help
                exit 0
                ;;
            *)
                echo "Unknown option: ${1}"
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
    local events
    events="create,delete,modify,move"
    if [[ "${include_access}" = true ]]; then
        events+=",access"
    fi

    if [[ ! -d "${monitor_dir}" ]]; then
        echo -e "${eventcolors[DELETE]}[ERROR]${eventcolors[RESET]} The directory to monitor does not exist."
        exit 1
    fi

    echo "Monitoring directory: ${monitor_dir}"
    inotifywait -mre "${events}" "${monitor_dir}" |
    while read -r event; do
        printf -v timestamp '%(%m-%d-%Y %I:%M:%S %p)T' -1
        event_type=$(echo "$event" | awk '{print $2}')
        color=${eventcolors[$event_type]}
        event_log="[${timestamp}] ${event}"
        echo -e "${color}${event_log}${eventcolors[RESET]}"
        
        if [[ -n "${log_file}" ]]; then
            echo "${event_log}" >> "${log_file}"
        fi
    done
}

# Parse arguments
parse_arguments "${@}"

# Check if inotifywait is installed
check_command

# Monitor the directory
monitor_directory
