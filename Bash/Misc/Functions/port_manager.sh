#!/usr/bin/env bash

# Author: SlyFox1186
# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Misc/Functions/port_manager.sh
# Updated: 06-29-2024

port_manager() {
    local action=""
    local port_number=""
    local verbose=false

    display_help() {
        cat <<EOF
Usage: port_manager [options] <action> [port]

Options:
  -h, --help          Display this help message and return
  -v, --verbose       Enable verbose output

Actions:
  list                List all open ports and firewall rules
  check <port>        Check if a specific port is open or allowed in firewall
  open <port>         Open a specific port in the firewall
  close <port>        Close an open port and remove firewall rule

Port format: single port (80), comma-separated (80,443), or range (8000-9000)

Examples:
  port_manager list
  port_manager check 80
  port_manager open 80,443
  port_manager close 8000-9000
EOF
    }

    check_dependencies() {
        for cmd in ss iptables; do
            if ! command -v "$cmd" &>/dev/null; then
                echo "Error: $cmd is not installed. Please install it and try again."
                return 1
            fi
        done
    }

    log_action() {
        local log_file="/var/log/port_manager.log"
        echo "$(date): $1" | sudo tee -a "$log_file" > /dev/null
    }

    # Iterate over ports from a comma-separated/range spec, calling a callback for each
    _for_each_port() {
        local port_spec="$1"
        local callback="$2"

        IFS=',' read -ra entries <<< "$port_spec"
        for entry in "${entries[@]}"; do
            if [[ "$entry" =~ ^[0-9]+$ ]]; then
                "$callback" "$entry"
            elif [[ "$entry" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                for ((i=BASH_REMATCH[1]; i<=BASH_REMATCH[2]; i++)); do
                    "$callback" "$i"
                done
            else
                echo "Invalid port or range: $entry"
            fi
        done
    }

    list_ports() {
        $verbose && echo "Listing all open ports and firewall rules..."
        echo "Listening ports:"
        sudo ss -tuln | grep LISTEN | awk '{print $5}' | rev | cut -d: -f1 | rev | sort -n | uniq | while IFS= read -r port; do
            echo "  $port"
        done
        echo

        echo "Firewall rules (allowed incoming):"
        echo

        echo "iptables rules:"
        sudo iptables -L INPUT -n | awk '$1=="ACCEPT" {print $0}' |
            grep -oP 'dpt:\K\d+' | sort -n | uniq | while IFS= read -r port; do
            echo "  $port (iptables)"
        done
        echo

        if command -v ufw &>/dev/null; then
            echo "UFW rules:"
            sudo ufw status | grep ALLOW | awk '{print $1}' | sort -n | uniq | while IFS= read -r port; do
                echo "  $port (UFW)"
            done
            echo
        fi

        if command -v firewall-cmd &>/dev/null; then
            echo "firewalld rules:"
            sudo firewall-cmd --list-ports | tr ' ' '\n' | sort -n | uniq | while IFS= read -r port; do
                echo "  $port (firewalld)"
            done
            echo
        fi
    }

    _check_single_port() {
        local port="$1"
        if ss -tuln | grep -q ":${port} "; then
            echo "Port $port is listening."
        elif sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null ||
             sudo iptables -C INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null; then
            echo "Port $port is allowed in the firewall but not currently listening."
        else
            echo "Port $port is not open or allowed in the firewall."
        fi
    }

    check_port() {
        if [[ -z "$port_number" ]]; then
            echo "Error: Port number(s) not specified."
            display_help
            return 1
        fi
        _for_each_port "$port_number" _check_single_port
    }

    _open_single_port() {
        local port="$1"
        $verbose && echo "Opening port $port in the firewall..."
        sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        sudo iptables -A INPUT -p udp --dport "$port" -j ACCEPT
        echo "Port $port has been allowed in the firewall."
        log_action "Opened port $port"
    }

    open_port() {
        if [[ -z "$port_number" ]]; then
            echo "Error: Port number not specified."
            display_help
            return 1
        fi

        _for_each_port "$port_number" _open_single_port

        # Offer to add to UFW or firewalld
        if command -v ufw &>/dev/null; then
            read -rp "Add these ports to the UFW firewall whitelist? (y/n): " choice
            if [[ "$choice" == [yY]* ]]; then
                _for_each_port "$port_number" _ufw_allow
                echo "Reloading firewall..."
                sudo ufw reload
            fi
        elif command -v firewall-cmd &>/dev/null; then
            read -rp "Add these ports to the firewalld whitelist? (y/n): " choice
            if [[ "$choice" == [yY]* ]]; then
                _for_each_port "$port_number" _firewalld_allow
                echo "Reloading firewall..."
                sudo firewall-cmd --reload
            fi
        fi
    }

    _ufw_allow() {
        sudo ufw allow "$1"
        log_action "Added port $1 to UFW"
    }

    _ufw_deny() {
        sudo ufw delete allow "$1"
        log_action "Removed port $1 from UFW"
    }

    _firewalld_allow() {
        sudo firewall-cmd --permanent --add-port="$1/tcp"
        sudo firewall-cmd --permanent --add-port="$1/udp"
        log_action "Added port $1 to firewalld"
    }

    _firewalld_deny() {
        sudo firewall-cmd --permanent --remove-port="$1/tcp"
        sudo firewall-cmd --permanent --remove-port="$1/udp"
        log_action "Removed port $1 from firewalld"
    }

    _close_single_port() {
        local port="$1"
        $verbose && echo "Closing port $port..."
        sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
        sudo iptables -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || true
        echo "Firewall rule for port $port has been removed."
        log_action "Closed port $port"

        local pid
        pid=$(sudo lsof -t -i:"$port" 2>/dev/null) || true
        if [[ -n "$pid" ]]; then
            read -rp "Process with PID $pid is using port $port. Terminate it? (y/n): " terminate
            if [[ "$terminate" == [yY]* ]]; then
                $verbose && echo "Terminating process using port $port (PID $pid)..."
                if sudo kill "$pid"; then
                    echo "Process using port $port has been terminated."
                    log_action "Terminated process $pid using port $port"
                else
                    echo "Error: Failed to terminate the process using port $port."
                fi
            fi
        fi
    }

    close_port() {
        if [[ -z "$port_number" ]]; then
            echo "Error: Port number not specified."
            display_help
            return 1
        fi

        read -rp "Are you sure you want to close port(s) $port_number? (y/n): " confirm
        if [[ "$confirm" != [yY]* ]]; then
            return 0
        fi

        _for_each_port "$port_number" _close_single_port

        if command -v ufw &>/dev/null; then
            _for_each_port "$port_number" _ufw_deny
            echo "Reloading firewall..."
            sudo ufw reload
        elif command -v firewall-cmd &>/dev/null; then
            _for_each_port "$port_number" _firewalld_deny
            echo "Reloading firewall..."
            sudo firewall-cmd --reload
        fi
    }

    parse_arguments() {
        if [[ $# -eq 0 ]]; then
            display_help
            return 1
        fi

        while [[ $# -gt 0 ]]; do
            case "$1" in
                -h|--help)    display_help; return 0 ;;
                -v|--verbose) verbose=true; shift ;;
                list|check|open|close)
                    action="$1"
                    if [[ "$1" != "list" ]]; then
                        port_number="${2:-}"
                        shift
                    fi
                    shift
                    ;;
                *)
                    echo "Error: Invalid option or action: $1"
                    display_help
                    return 1
                    ;;
            esac
        done

        if [[ -z "$action" ]]; then
            echo "Error: Action not specified."
            display_help
            return 1
        fi
    }

    main() {
        check_dependencies || return 1
        parse_arguments "$@" || return $?

        $verbose && echo "Action: $action" && [[ -n "$port_number" ]] && echo "Port: $port_number"

        case "$action" in
            list)  list_ports;  log_action "Listed ports" ;;
            check) check_port;  log_action "Checked port(s) $port_number" ;;
            open)  open_port;   log_action "Opened port(s) $port_number" ;;
            close) close_port;  log_action "Closed port(s) $port_number" ;;
        esac
    }

    main "$@"
}

port_manager "$@"
