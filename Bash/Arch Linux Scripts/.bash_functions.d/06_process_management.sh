#!/usr/bin/env bash
# Process Management Functions

## KILLALL COMMANDS ##
# The tkapt function is dangerously unsafe and has been removed.
# Use pacman_unlock_guide for help with locked package managers.

# Guides the user in safely resolving a locked pacman process.
pacman_unlock_guide() {
    echo "Checking for processes holding pacman lock..."
    if [[ -f /var/lib/pacman/db.lck ]]; then
        echo -e "\nFound pacman lock file: /var/lib/pacman/db.lck"
        echo "Checking if pacman is running..."
        if pgrep -x pacman &>/dev/null; then
            echo "pacman is currently running (PID: $(pgrep -x pacman))."
            echo -e "\nRecommended Steps:"
            echo "1. Wait for the current pacman operation to finish."
            echo "2. If it's stuck, try: 'sudo kill \$(pgrep -x pacman)'"
            echo "3. As a LAST RESORT: 'sudo kill -9 \$(pgrep -x pacman)'"
        else
            echo "No running pacman process found. The lock file may be stale."
            echo "You can safely remove it: 'sudo rm /var/lib/pacman/db.lck'"
        fi
    else
        echo "No pacman lock file found. Package manager is not locked."
    fi
}

kill_process() {
    local program pids id

    if [[ -z "$1" ]]; then
        echo "Usage: kill_process NAME"
        return 1
    fi

    program=$1

    echo -e "Checking for running instances of: '$program'\n"

    # Find all PIDs for the given process
    pids=$(pgrep -f "$program")

    if [[ -z "$pids" ]]; then
        echo "No instances of "$program" are running."
        return 0
    fi

    echo "Found instances of '$program' with PIDs: $pids"
    echo "Attempting to kill all instances of: '$program'"

    for id in $pids; do
        echo "Killing PID $id..."
        if ! sudo kill -9 "$id"; then
            echo "Failed to kill PID $id. Check your permissions."
            continue
        fi
    done

    echo -e "\nAll instances of '$program' were attempted to be killed."
}

## nohup commands
nh() {
    nohup "$1" &>/dev/null &
    echo
    ls -1AvhF --color --group-directories-first
}

nhs() {
    nohup sudo "$1" &>/dev/null &
    echo
    ls -1AvhF --color --group-directories-first
}

nhe() {
    nohup "$1" &>/dev/null &
    exit
}

nhse() {
    nohup sudo "$1" &>/dev/null &
    exit
}

# Run Python scripts with options
run_py() {
    local cmd_prefix="clear; "
    local flush_cmd=""

    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                cmd_prefix=""  # Disable screen clearing
                ;;
            -f|--flush)
                flush_cmd="redis-cli flushall && "  # Add Redis flush command
                ;;
            -h|--help)
                echo "Usage: run_app [OPTIONS]"
                echo "Options:"
                echo "  -v, --verbose   Run without clearing the screen"
                echo "  -f, --flush     Run 'redis-cli flushall' before execution"
                echo "  -h, --help      Show this help menu"
                return 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use -h or --help for usage information."
                return 1
                ;;
        esac
        shift
    done

    # Run the appropriate Python script
    if [[ -f "app.py" ]]; then
        eval "${cmd_prefix}${flush_cmd}python3 app.py"
    elif [[ -f "main.py" ]]; then
        eval "${cmd_prefix}${flush_cmd}python3 main.py"
    else
        echo "No app.py or main.py found."
        return 1
    fi
}

# Test Python scripts
mypt() {
    clear
    if [[ -n "$1" ]]; then
        pytest -v "$@"
        return 0
    else
        printf "\n%s\n" "Please pass a script to the function."
        return 1
    fi
}

myptd() {
    clear
    if [[ -n "$1" ]]; then
        pytest -v --log-cli-level=DEBUG "$@"
            return 0
        else
            printf "\n%s\n" "Please pass a script to the function."
            return 1
        fi
}
