#!/usr/bin/env bash

# Author: SlyFox1186
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Misc/Functions/port_manager.sh
# Updated: 06-29-2024

port_manager() {
    # Global Variables
    declare -a ports
    local action=""
    local port_number=""
    local verbose=false

    # Display Help Menu
    display_help() {
        local function_name="port_manager"
        echo "Usage: $function_name [options] <action> [port]"
        echo
        echo "Options:"
        echo "  -h, --help          Display this help message and return"
        echo "  -v, --verbose       Enable verbose output"
        echo
        echo "Actions:"
        echo "  list                List all open ports and firewall rules"
        echo "  check <port>        Check if a specific port is open or allowed in firewall"
        echo "  open <port>         Open a specific port in the firewall"
        echo "  close <port>        Close an open port and remove firewall rule"
        echo
        echo "Examples:"
        echo "  $function_name list"
        echo "  $function_name check 80"
        echo "  $function_name open 80"
        echo "  $function_name close 80"
    }

    # Check for required commands
    check_dependencies() {
        for cmd in ss iptables; do
            if ! command -v $cmd &>/dev/null; then
                echo "Error: $cmd is not installed. Please install it and try again."
                return 1
            fi
        done
    }

    # Log function
    log_action() {
        local log_file="/var/log/port_manager.log"
        echo "$(date): $1" | sudo tee -a $log_file > /dev/null
    }

    # List all open ports and firewall rules
    list_ports() {
        if $verbose; then echo "Listing all open ports and firewall rules..."; fi
        echo "Listening ports:"
        sudo ss -tuln | grep LISTEN | awk '{print $5}' | cut -d: -f2 | sort -n | uniq | while read port; do
            echo "  $port"
        done
        echo

        echo "Firewall rules (allowed incoming):"
        echo
        
        # Check iptables
        echo "iptables rules:"
        sudo iptables -L INPUT -n | awk '$1=="ACCEPT" {print $0}' | 
            grep -oP 'dpt:\K\d+' | sort -n | uniq | while read port; do
            echo "  $port (iptables)"
        done
        echo

        # Check UFW if available
        if command -v ufw &>/dev/null; then
            echo "UFW rules:"
            sudo ufw status | grep ALLOW | awk '{print $1}' | sort -n | uniq | while read port; do
                echo "  $port (UFW)"
            done
            echo
        fi

        # Check firewalld if available
        if command -v firewall-cmd &>/dev/null; then
            echo "firewalld rules:"
            sudo firewall-cmd --list-ports | tr ' ' '\n' | sort -n | uniq | while read port; do
                echo "  $port (firewalld)"
            done
            echo
        fi
    }

    # Check if specific ports are open or allowed in the firewall
    check_port() {
        if [[ -z "$port_number" ]]; then
            echo "Error: Port number(s) not specified."
            display_help
            return 1
        fi

        IFS=',' read -ra ADDR <<< "$port_number"
        for port in "${ADDR[@]}"; do
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                if ss -tuln | grep -q ":$port "; then
                    echo "Port $port is listening."
                elif sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null || 
                     sudo iptables -C INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null; then
                    echo "Port $port is allowed in the firewall but not currently listening."
                else
                    # Check for port ranges
                    if sudo iptables-save | grep -qE "(-A|-I) INPUT .* --dports [0-9]+:[0-9]+ .*-j ACCEPT" &&
                       awk -v port="$port" '
                       $1 ~ /^(-A|-I)$/ && $2 == "INPUT" && $0 ~ /--dports/ {
                           split($0, a, "--dports ");
                           split(a[2], b, " ");
                           split(b[1], range, ":");
                           if (port >= range[1] && port <= range[2]) 
                               exit 0;
                       }
                       END {exit 1}
                       ' <(sudo iptables-save); then
                        echo "Port $port is allowed in the firewall (within a port range) but not currently listening."
                    else
                        echo "Port $port is not open or allowed in the firewall."
                    fi
                fi
            elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -ra RANGE <<< "$port"
                for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                    if ss -tuln | grep -q ":$i "; then
                        echo "Port $i is listening."
                    elif sudo iptables -C INPUT -p tcp --dport "$i" -j ACCEPT &>/dev/null || 
                         sudo iptables -C INPUT -p udp --dport "$i" -j ACCEPT &>/dev/null; then
                        echo "Port $i is allowed in the firewall but not currently listening."
                    else
                        # Check for port ranges
                        if sudo iptables-save | grep -qE "(-A|-I) INPUT .* --dports [0-9]+:[0-9]+ .*-j ACCEPT" &&
                           awk -v port="$i" '
                           $1 ~ /^(-A|-I)$/ && $2 == "INPUT" && $0 ~ /--dports/ {
                               split($0, a, "--dports ");
                               split(a[2], b, " ");
                               split(b[1], range, ":");
                               if (port >= range[1] && port <= range[2]) 
                                   exit 0;
                           }
                           END {exit 1}
                           ' <(sudo iptables-save); then
                            echo "Port $i is allowed in the firewall (within a port range) but not currently listening."
                        else
                            echo "Port $i is not open or allowed in the firewall."
                        fi
                    fi
                done
            else
                echo "Invalid port or range: $port"
            fi
        done
    }

    # Open a specific port in the firewall
    open_port() {
        if [[ -z "$port_number" ]]; then
            echo "Error: Port number not specified."
            display_help
            return 1
        fi

        IFS=',' read -ra ADDR <<< "$port_number"
        for port in "${ADDR[@]}"; do
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                if $verbose; then echo "Opening port $port in the firewall..."; fi
                sudo iptables -A INPUT -p tcp --dport $port -j ACCEPT
                sudo iptables -A INPUT -p udp --dport $port -j ACCEPT
                echo "Port $port has been allowed in the firewall."
                log_action "Opened port $port"
            elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -ra RANGE <<< "$port"
                for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                    if $verbose; then echo "Opening port $i in the firewall..."; fi
                    sudo iptables -A INPUT -p tcp --dport $i -j ACCEPT
                    sudo iptables -A INPUT -p udp --dport $i -j ACCEPT
                    echo "Port $i has been allowed in the firewall."
                    log_action "Opened port $i"
                done
            else
                echo "Invalid port or range: $port"
            fi
        done

        # Check for firewall and prompt user
        if command -v ufw &>/dev/null; then
            read -p "Would you like to add these ports to the UFW firewall whitelist? (y/n): " choice
            if [[ "$choice" == "y" ]]; then
                for port in "${ADDR[@]}"; do
                    if [[ "$port" =~ ^[0-9]+$ ]]; then
                        sudo ufw allow $port
                        log_action "Added port $port to UFW"
                    elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                        IFS='-' read -ra RANGE <<< "$port"
                        for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                            sudo ufw allow $i
                            log_action "Added port $i to UFW"
                        done
                    fi
                done
                echo "Attempting to restart the firewall. This may take a moment..."
                sudo ufw reload
            fi
        elif command -v firewall-cmd &>/dev/null; then
            read -p "Would you like to add these ports to the firewalld whitelist? (y/n): " choice
            if [[ "$choice" == "y" ]]; then
                for port in "${ADDR[@]}"; do
                    if [[ "$port" =~ ^[0-9]+$ ]]; then
                        sudo firewall-cmd --permanent --add-port=$port/tcp
                        sudo firewall-cmd --permanent --add-port=$port/udp
                        log_action "Added port $port to firewalld"
                    elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                        IFS='-' read -ra RANGE <<< "$port"
                        for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                            sudo firewall-cmd --permanent --add-port=$i/tcp
                            sudo firewall-cmd --permanent --add-port=$i/udp
                            log_action "Added port $i to firewalld"
                        done
                    fi
                done
                echo "Attempting to restart the firewall. This may take a moment..."
                sudo firewall-cmd --reload
            fi
        fi
    }

    # Close an open port and remove the firewall rule
    close_port() {
        if [[ -z "$port_number" ]]; then
            echo "Error: Port number not specified."
            display_help
            return 1
        fi

        IFS=',' read -ra ADDR <<< "$port_number"
        for port in "${ADDR[@]}"; do
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                read -p "Are you sure you want to close port $port? (y/n): " confirm
                if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                    if $verbose; then echo "Closing port $port..."; fi
                    sudo iptables -D INPUT -p tcp --dport $port -j ACCEPT
                    sudo iptables -D INPUT -p udp --dport $port -j ACCEPT
                    echo "Firewall rule for port $port has been removed."
                    log_action "Closed port $port"
                    
                    local pid=$(sudo lsof -t -i:$port)
                    if [[ -n "$pid" ]]; then
                        read -p "Process with PID $pid is using port $port. Terminate it? (y/n): " terminate
                        if [[ $terminate == [yY] || $terminate == [yY][eE][sS] ]]; then
                            if $verbose; then echo "Terminating process using port $port (PID $pid)..."; fi
                            if sudo kill -9 $pid; then
                                echo "Process using port $port has been terminated."
                                log_action "Terminated process $pid using port $port"
                            else
                                echo "Error: Failed to terminate the process using port $port."
                            fi
                        fi
                    fi
                fi
            elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -ra RANGE <<< "$port"
                read -p "Are you sure you want to close ports ${RANGE[0]}-${RANGE[1]}? (y/n): " confirm
                if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                    for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                        if $verbose; then echo "Closing port $i..."; fi
                        sudo iptables -D INPUT -p tcp --dport $i -j ACCEPT
                        sudo iptables -D INPUT -p udp --dport $i -j ACCEPT
                        echo "Firewall rule for port $i has been removed."
                        log_action "Closed port $i"
                        
                        local pid=$(sudo lsof -t -i:$i)
                        if [[ -n "$pid" ]]; then
                            read -p "Process with PID $pid is using port $i. Terminate it? (y/n): " terminate
                            if [[ $terminate == [yY] || $terminate == [yY][eE][sS] ]]; then
                                if $verbose; then echo "Terminating process using port $i (PID $pid)..."; fi
                                if sudo kill -9 $pid; then
                                    echo "Process using port $i has been terminated."
                                    log_action "Terminated process $pid using port $i"
                                else
                                    echo "Error: Failed to terminate the process using port $i."
                                fi
                            fi
                        fi
                    done
                fi
            else
                echo "Invalid port or range: $port"
            fi
        done

        # Remove from UFW or firewalld if present
        if command -v ufw &>/dev/null; then
            for port in "${ADDR[@]}"; do
                if [[ "$port" =~ ^[0-9]+$ ]]; then
                    sudo ufw delete allow $port
                    log_action "Removed port $port from UFW"
                elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                    IFS='-' read -ra RANGE <<< "$port"
                    for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                        sudo ufw delete allow $i
                        log_action "Removed port $i from UFW"
                    done
                fi
            done
            echo "Attempting to restart the firewall. This may take a moment..."
            sudo ufw reload
        elif command -v firewall-cmd &>/dev/null; then
            for port in "${ADDR[@]}"; do
                if [[ "$port" =~ ^[0-9]+$ ]]; then
                    sudo firewall-cmd --permanent --remove-port=$port/tcp
                    sudo firewall-cmd --permanent --remove-port=$port/udp
                    log_action "Removed port $port from firewalld"
                elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                    IFS='-' read -ra RANGE <<< "$port"
                    for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                        sudo firewall-cmd --permanent --remove-port=$i/tcp
                        sudo firewall-cmd --permanent --remove-port=$i/udp
                        log_action "Removed port $i from firewalld"
                    done
                fi
            done
            echo "Attempting to restart the firewall. This may take a moment..."
            sudo firewall-cmd --reload
        fi
    }

    # Parse arguments
    parse_arguments() {
        if [[ $# -eq 0 ]]; then
            display_help
            return 1
        else
            while [[ $# -gt 0 ]]; do
                case $1 in
                    -h|--help)
                        display_help
                        return 0
                        ;;
                    -v|--verbose)
                        verbose=true
                        shift
                        ;;
                    list|check|open|close)
                        action=$1
                        if [[ $1 != "list" ]]; then
                            port_number=$2
                            shift
                        fi
                        shift
                        ;;
                    *)
                        echo "Error: Invalid option or action."
                        display_help
                        return 1
                        ;;
                esac
            done
        fi

        if [[ -z $action ]]; then
            echo "Error: Action not specified."
            display_help
            return 1
        fi
    }

    # Main function
    main() {
        check_dependencies
        if ! parse_arguments "$@"; then
            return 1
        fi
        
        if [[ "$verbose" == true ]]; then
            echo "Action: $action"
            [[ -n "$port_number" ]] && echo "Port: $port_number"
        fi
        
        case $action in
            list)
                list_ports
                log_action "Listed ports"
                ;;
            check)
                check_port
                log_action "Checked port(s) $port_number"
                ;;
            open)
                open_port
                log_action "Opened port(s) $port_number"
                ;;
            close)
                close_port
                log_action "Closed port(s) $port_number"
                ;;
        esac
    }

    # Execute main function
    main "$@"
}

port_manager
