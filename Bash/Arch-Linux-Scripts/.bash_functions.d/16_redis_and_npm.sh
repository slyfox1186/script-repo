#!/usr/bin/env bash

function rbi() {
    clear
    if [[ -d frontend ]]; then
        pushd frontend
    fi
    if [[ -d node_modules ]]; then
        rm -fr node_modules
    fi
    npm install
    if [[ -d build ]]; then
        rm -fr build 
    fi
    npm run dev
    popd
    if [[ -d backend ]]; then
        pushd backend
    fi
    if [[ -f app.py ]]; then
        python3 app.py
    fi
    popd
}

function rbl() {
    if [[ -d frontend ]]; then
        FLAG=1
	    pushd frontend
    fi
    npm run lint
    if [[ "${FLAG}" -eq 1 ]]; then
        popd
    fi
    unset FLAG
}


killpy() {
    local script_name="${1:-app.py}"
    echo "Searching for Python processes running '${script_name}'..."

    # Use pgrep to find PIDs by matching the full command-line (-f).
    # The [a]pp.py pattern avoids pgrep matching its own process.
    local pids
    pids=$(pgrep -f "python.*[ /]${script_name}")

    if [[ -z "$pids" ]]; then
        echo "No running Python processes found for '${script_name}'."
        return 0
    fi

    echo "Found PIDs: ${pids}. Attempting graceful shutdown (SIGTERM)..."
    # Try to kill gracefully first. No signal number means SIGTERM.
    if sudo kill ${pids}; then
        sleep 2
        # Check if processes are still alive
        if pgrep -f "python.*[ /]${script_name}" > /dev/null; then
            echo "Process(es) still running. Forcing shutdown (SIGKILL)..."
            if sudo kill -9 ${pids}; then
                echo "Successfully sent SIGKILL."
            else
                echo "Error: Failed to send SIGKILL." >&2
                return 1
            fi
        else
            echo "Process(es) terminated gracefully."
        fi
    else
        echo "Error: Failed to send SIGTERM. Check permissions." >&2
        return 1
    fi
}


rsearch() {
    clear
    redis-cli KEYS "memory_b:*" |
    while read key; do redis-cli --raw JSON.GET "$key" |
    jq -r '.text + " (Importance: " + (.importance|tostring) + ")"'; done |
    sort -V
}
