#!/usr/bin/env bash
# Process Management Functions

## KILLALL COMMANDS ##
tkapt() {
    local program
    local list=(apt apt-get aptitude dpkg)
    for program in ${list[@]}; do
        sudo killall -9 "$program" 2>/dev/null
    done
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