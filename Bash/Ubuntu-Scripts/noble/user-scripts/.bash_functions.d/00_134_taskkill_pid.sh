#!/usr/bin/env bash

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
