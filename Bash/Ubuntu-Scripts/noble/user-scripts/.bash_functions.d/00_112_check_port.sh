#!/usr/bin/env bash

# Check Port Numbers
check_port() {
    local choice key name pid port protocol
    local process_found=false
    local -A pid_protocol_map=()

    if (($# > 0)); then
        port="$1"
    else
        read -r -p 'Enter the port number: ' port
    fi

    if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        printf 'Invalid port: %s\n' "$port" >&2
        return 1
    fi

    echo -e "\nChecking for processes using port $port...\n"

    while IFS= read -r pid name protocol; do
        [[ -n $pid && -n $name ]] && {
            process_found=true
            [[ ${pid_protocol_map[$pid,$name]} != *"$protocol"* ]] &&
                pid_protocol_map[$pid,$name]+="$protocol "
        }
    done < <(lsof -i :"$port" -nP | awk '$1 != "COMMAND" {print $2, $1, $8}')

    for key in "${!pid_protocol_map[@]}"; do
        IFS=',' read -r pid name <<< "$key"
        protocol=${pid_protocol_map[$key]% }

        echo -e "Process: $name (PID: $pid) using ${protocol// /, }"

        if [[ $protocol == *"TCP"*"UDP"* ]]; then
            echo -e "\nBoth TCP and UDP are used by the same process.\n"
            read -r -p "Kill it? (yes/no): " choice
        else
            read -r -p "Kill this process? (yes/no): " choice
        fi

        case "$choice" in
            [Yy]|[Yy][Ee][Ss]|"")
                echo -e "\nKilling process $pid...\n"
                kill -9 "$pid" 2>/dev/null &&
                    echo -e "Process $pid killed successfully.\n" ||
                    echo -e "Failed to kill process $pid. It may have already exited or you lack permissions.\n"
                ;;
            [Nn]|[Nn][Oo])
                echo -e "\nProcess $pid not killed.\n" ;;
            *)
                echo -e "\nInvalid response. Exiting.\n"
                return 1
                ;;
        esac
    done

    [[ $process_found == "false" ]] && echo -e "No process is using port $port.\n"
}
