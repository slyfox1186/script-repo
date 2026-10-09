#!/usr/bin/env bash
# Process Management Functions

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
        echo "No instances of '$program' are running."
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
    nhe "$@" || return
    echo
    ls -1AvhF --color --group-directories-first
}

nhs() {
    nhse "$@" || return
    echo
    ls -1AvhF --color --group-directories-first
}

nhe() {
    if (($# == 0)); then
        printf 'Usage: nhe COMMAND [ARGUMENTS...]\n' >&2
        return 1
    fi
    nohup "$@" &>/dev/null &
    return 0
}

nhse() {
    if (($# == 0)); then
        printf 'Usage: nhse COMMAND [ARGUMENTS...]\n' >&2
        return 1
    fi
    # Authenticate in the foreground before the detached command suppresses output.
    sudo -v || return
    nhe sudo -n -- "$@"
}

taskkill_pid() {
    local pid port
    local -a pids

    if [[ $# -eq 0 ]]; then
        echo "Usage: tkpid <port1> <port2> <port3> ..."
        echo "Example: tkpid 1234 4456 8080"
        return 1
    fi

    printf 'Killing processes on ports: %s\n' "$*"

    for port in "$@"; do
        echo "Checking port $port..."

        # Get PIDs using the port (suppress all warnings)
        mapfile -t pids < <(lsof -t -i :"$port" 2>/dev/null | head -n 20)

        if ((${#pids[@]} == 0)); then
            echo "  No processes found on port $port"
            continue
        fi

        printf '  Found processes on port %s: %s\n' "$port" "${pids[*]}"

        # Kill each PID (suppress warnings)
        for pid in "${pids[@]}"; do
            echo "  Killing process $pid on port $port..."
            kill -9 "$pid" &>/dev/null

            # Check if it was actually killed (suppress warnings)
            if kill -0 "$pid" &>/dev/null; then
                echo "  Failed to kill process $pid"
            else
                echo "  Successfully killed process $pid"
            fi
        done
    done

    echo "Done killing processes."
}

alias tkpid='taskkill_pid'
