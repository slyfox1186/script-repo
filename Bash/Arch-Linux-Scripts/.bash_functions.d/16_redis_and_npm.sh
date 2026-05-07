#!/usr/bin/env bash

function rbi() {
    clear
    if [[ -d frontend ]]; then
        pushd frontend >/dev/null || return 1
        if [[ -d node_modules ]]; then
            rm -fr node_modules
        fi
        npm install
        if [[ -d build ]]; then
            rm -fr build
        fi
        npm run dev
        popd >/dev/null || return 1
    fi
    if [[ -d backend ]]; then
        pushd backend >/dev/null || return 1
        if [[ -f app.py ]]; then
            python3 app.py
        fi
        popd >/dev/null || return 1
    fi
}

function rbl() {
    if [[ -d frontend ]]; then
        pushd frontend >/dev/null || return 1
        npm run lint
        popd >/dev/null || return 1
    else
        npm run lint
    fi
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
    while read -r key; do redis-cli --raw JSON.GET "$key" |
    jq -r '.text + " (Importance: " + (.importance|tostring) + ")"'; done |
    sort -V
}
