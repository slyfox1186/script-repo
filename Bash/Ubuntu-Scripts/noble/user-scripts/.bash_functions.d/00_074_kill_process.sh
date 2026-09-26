#!/usr/bin/env bash

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
