#!/usr/bin/env bash


check_port() {
    local choice kill_choice pid name protocol

    if [ -z "$1" ]; then
        read -p 'Enter the port number: ' choice
    else
        choice="$1"
    fi

    if [ -z "$choice" ] && [ -z "$1" ]; then
        echo "Error: No port was specified. Please pass the port to the function or enter it when prompted."
        return 1
    fi

    echo "Checking for processes using port $choice..."

    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | awk '{print $1}')
        protocol=$(echo "$line" | awk '{print $8}')

        if [ -n "$pid" ] && [ -n "$name" ]; then
            echo "Process using port $choice: $name (PID: $pid, Protocol: $protocol)"
            read -p "Do you want to kill this process? (yes/no): " kill_choice

            shopt -s nocasematch
            case "$kill_choice" in
                yes|y|"") sudo kill -9 "$pid"
                          echo "Process $pid killed."
                          ;;
                no|n)     echo "Process $pid not killed."
                          ;;
                *)        echo "Invalid option. Exiting." ;;
            esac
            shopt -u nocasematch
        else
            echo "No process is using port $choice."
        fi
    done < <(sudo lsof -i :"$choice" -nP | grep -v "COMMAND")
}

check_port "$@"
