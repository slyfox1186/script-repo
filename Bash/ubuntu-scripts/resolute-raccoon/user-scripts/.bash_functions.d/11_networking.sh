#!/usr/bin/env bash
# Networking and Download Functions

## ARIA2 COMMANDS ##

# Start the aria2 daemon in the background.
aria2_on() {
    if aria2c --conf-path="$HOME/.aria2/aria2.conf" --daemon=true; then
        echo
        echo "Command Executed Successfully"
    else
        echo
        echo "Command Failed"
        return 1
    fi
}

# Stop aria2 daemon
aria2_off() {
    clear
    killall aria2c
}

myip() {
    echo "LAN: $(ip route get 1.2.3.4 | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
    echo "WAN: $(curl -fsS "https://checkip.amazonaws.com")"
}

# WGET command
mywget() {
    local outfile url
    if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        read -r -p "Please enter the output file name: " outfile
        read -r -p "Please enter the URL: " url
        echo
        wget --output-document="$outfile" -- "$url"
    else
        wget --output-document="$1" -- "$2"
    fi
}

############
## ARIA2C ##
############

# Usage: adl FILENAME URL
# Downloads URL with the aria2 configuration in ~/.aria2. A FILENAME without an extension
# gets .mp4.
adl() {
    local file url

    if (($# != 2)); then
        echo "Error: Two arguments are required: output file and download URL"
        return 1
    fi
    if ! command -v aria2c &>/dev/null; then
        echo "aria2c is not installed. Install it with: sudo apt -y install aria2"
        return 1
    fi
    if [[ ! -f "$HOME/.aria2/aria2.conf" ]]; then
        echo "The aria2 configuration is missing: $HOME/.aria2/aria2.conf"
        return 1
    fi

    file="$1"
    url="$2"
    [[ "${file##*/}" == *.* ]] || file+=".mp4"
    aria2c --conf-path="$HOME/.aria2/aria2.conf" --out="$file" "$url"
}

padl() {
    local clipboard
    local -a args

    if command -v xclip &>/dev/null; then
        clipboard=$(xclip -o -selection clipboard) || return
    elif command -v pwsh.exe &>/dev/null; then
        clipboard=$(pwsh.exe -NoProfile -Command 'Get-Clipboard -Raw') || return
    else
        printf 'padl requires xclip (Linux) or pwsh.exe (Windows).\n' >&2
        return 1
    fi
    clipboard=${clipboard//$'\r'/}
    read -r -a args <<< "${clipboard//$'\n'/ }"
    if ((${#args[@]} != 2)); then
        printf 'Clipboard must contain: FILENAME URL (filename cannot contain spaces).\n' >&2
        return 1
    fi
    adl "${args[0]}" "${args[1]}"
}

# Domain Lookup
dlu() {
    local script="/usr/local/bin/domain_lookup.py" temp
    local url="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/domain_lookup.py"
    local -a domain_list=("$@")

    if ((${#domain_list[@]} == 0)); then
        read -r -a domain_list -p "Enter the domain(s) to pass: " || return 1
    fi
    if ((${#domain_list[@]} == 0)); then
        printf 'Usage: dlu DOMAIN...\n' >&2
        return 1
    fi

    if [[ ! -s "$script" ]]; then
        temp=$(mktemp) || return
        if ! wget -qO "$temp" "$url" || [[ ! -s "$temp" ]]; then
            printf 'Failed to download %s\n' "$url" >&2
            rm -f -- "$temp"
            return 1
        fi
        if ! sudo install -m 755 -- "$temp" "$script"; then
            rm -f -- "$temp"
            return 1
        fi
        rm -f -- "$temp"
    fi
    python3 "$script" "${domain_list[@]}"
}

# Usage: check_port [PORT]
# Lists the processes listening on PORT and offers to stop them.
check_port() {
    local name pid port="${1-}" protocol
    local -a pids=()

    if [[ -z "$port" ]]; then
        read -r -p 'Enter the port number: ' port || return 1
    fi
    if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        printf 'Invalid port: %s\n' "$port" >&2
        return 1
    fi

    printf '\nChecking for processes listening on port %s...\n\n' "$port"
    while IFS=$'\t' read -r pid name protocol; do
        printf 'Process: %s (PID: %s) using %s\n' "$name" "$pid" "$protocol"
        pids+=("$pid")
    done < <(_port_listeners "$port")

    if ((${#pids[@]} == 0)); then
        printf 'No process is listening on port %s.\n' "$port"
        return 0
    fi
    echo
    mapfile -t pids < <(printf '%s\n' "${pids[@]}" | sort -un)
    _terminate_pids --sudo "${pids[@]}"
}

port_manager() (
    local action="" port_number="" verbose=false

    display_help() {
        local function_name="port_manager"
        echo "Usage: $function_name [options] <action> [ports]"
        echo
        echo "Options:"
        echo "  -h, --help          Display this help message and return"
        echo "  -v, --verbose       Enable verbose output"
        echo
        echo "Actions:"
        echo "  list                List listening ports and firewall rules"
        echo "  check <ports>       Check whether ports are listening or allowed in the firewall"
        echo "  open <ports>        Allow ports in the active firewall"
        echo "  close <ports>       Remove firewall rules and optionally stop listening processes"
        echo
        echo "Ports are comma-separated numbers or ranges, such as 80,443,8000-8010."
        echo
        echo "Examples:"
        echo "  $function_name list"
        echo "  $function_name check 80"
        echo "  $function_name open 80,443"
        echo "  $function_name close 8000-8010"
    }

    check_dependencies() {
        local cmd
        for cmd in ss iptables; do
            if ! command -v "$cmd" &>/dev/null; then
                echo "Error: $cmd is not installed. Please install it and try again."
                return 1
            fi
        done
    }

    log_action() {
        printf '%s: %s\n' "$(date)" "$1" | sudo tee -a /var/log/port_manager.log > /dev/null
    }

    # Prints one port per line from a list such as "80,8000-8002"; fails on any invalid item.
    expand_ports() {
        local item first last port
        local -a items
        IFS=',' read -r -a items <<< "$1"
        ((${#items[@]})) || return 1
        for item in "${items[@]}"; do
            if [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                first=${BASH_REMATCH[1]} last=${BASH_REMATCH[2]}
            elif [[ "$item" =~ ^[0-9]+$ ]]; then
                first=$item last=$item
            else
                printf 'Invalid port or range: %s\n' "$item" >&2
                return 1
            fi
            if ((first < 1 || last > 65535 || first > last)); then
                printf 'Invalid port or range: %s\n' "$item" >&2
                return 1
            fi
            for ((port = first; port <= last; port++)); do
                printf '%s\n' "$port"
            done
        done
    }

    # Prints ufw, firewalld or iptables: the firewall that should own new rules.
    firewall_backend() {
        if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
            echo ufw
        elif command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state &>/dev/null; then
            echo firewalld
        else
            echo iptables
        fi
    }

    # Succeeds when an iptables INPUT rule accepts PORT, alone or within a --dports range.
    iptables_allows() {
        local port="$1" protocol
        for protocol in tcp udp; do
            sudo iptables -C INPUT -p "$protocol" --dport "$port" -j ACCEPT &>/dev/null && return 0
        done
        sudo iptables-save | awk -v port="$port" '
            $1 ~ /^-[AI]$/ && $2 == "INPUT" && /-j ACCEPT/ && match($0, /--dports [0-9]+:[0-9]+/) {
                split(substr($0, RSTART + 9, RLENGTH - 9), range, ":")
                if (port + 0 >= range[1] + 0 && port + 0 <= range[2] + 0) found = 1
            }
            END { exit !found }'
    }

    list_ports() {
        if $verbose; then echo "Listing all open ports and firewall rules..."; fi
        echo "Listening ports:"
        sudo ss -Htuln | awk '{ count = split($5, address, ":"); print $1 "\t" address[count] }' |
            sort -t $'\t' -k2,2n -k1,1 -u | while IFS=$'\t' read -r protocol port; do
            echo "  $port/$protocol"
        done
        echo

        echo "Firewall rules (allowed incoming):"
        echo
        echo "iptables rules:"
        sudo iptables -S INPUT | awk '/-j ACCEPT/' | grep -oP -- '--dports? \K[0-9:]+' | sort -n -u |
            while read -r port; do
            echo "  $port (iptables)"
        done
        echo

        if command -v ufw &>/dev/null; then
            echo "UFW rules:"
            sudo ufw status | awk '/ALLOW/ { print $1 }' | sort -n -u | while read -r port; do
                echo "  $port (UFW)"
            done
            echo
        fi

        if command -v firewall-cmd &>/dev/null; then
            echo "firewalld rules:"
            sudo firewall-cmd --list-ports | tr ' ' '\n' | sort -n -u | while read -r port; do
                echo "  $port (firewalld)"
            done
            echo
        fi
    }

    port_manager_check() {
        local port port_list
        local -a ports
        if ! port_list=$(expand_ports "$port_number"); then
            display_help
            return 1
        fi
        mapfile -t ports <<< "$port_list"
        for port in "${ports[@]}"; do
            if [[ -n $(ss -Htuln "sport = :$port") ]]; then
                echo "Port $port is listening."
            elif iptables_allows "$port"; then
                echo "Port $port is allowed in the firewall but not currently listening."
            else
                echo "Port $port is not open or allowed in the firewall."
            fi
        done
    }

    open_port() {
        local backend port port_list protocol
        local -a ports
        if ! port_list=$(expand_ports "$port_number"); then
            display_help
            return 1
        fi
        mapfile -t ports <<< "$port_list"
        backend=$(firewall_backend)
        for port in "${ports[@]}"; do
            if $verbose; then echo "Opening port $port with $backend..."; fi
            case "$backend" in
                ufw)
                    sudo ufw allow "$port" || return
                    ;;
                firewalld)
                    sudo firewall-cmd --permanent --add-port="$port/tcp" --add-port="$port/udp" || return
                    ;;
                iptables)
                    for protocol in tcp udp; do
                        sudo iptables -C INPUT -p "$protocol" --dport "$port" -j ACCEPT &>/dev/null ||
                            sudo iptables -I INPUT -p "$protocol" --dport "$port" -j ACCEPT || return
                    done
                    ;;
            esac
            echo "Port $port has been allowed in the firewall."
            log_action "Opened port $port with $backend"
        done
        if [[ "$backend" == firewalld ]]; then
            sudo firewall-cmd --reload || return
        elif [[ "$backend" == iptables ]]; then
            echo "Note: raw iptables rules are lost at reboot unless saved, for example with iptables-persistent."
        fi
    }

    close_port() {
        local answer backend item port port_list protocol
        local -a items pids ports confirmed=()
        IFS=',' read -r -a items <<< "$port_number"
        if ! port_list=$(expand_ports "$port_number"); then
            display_help
            return 1
        fi
        mapfile -t ports <<< "$port_list"

        for item in "${items[@]}"; do
            read -r -p "Are you sure you want to close port(s) $item? (y/N): " answer || return 1
            if [[ $answer == [yY] || $answer == [yY][eE][sS] ]]; then
                mapfile -t -O "${#confirmed[@]}" confirmed < <(expand_ports "$item")
            fi
        done
        if ((${#confirmed[@]} == 0)); then
            echo "No ports were closed."
            return 0
        fi

        backend=$(firewall_backend)
        for port in "${confirmed[@]}"; do
            if $verbose; then echo "Closing port $port..."; fi
            for protocol in tcp udp; do
                while sudo iptables -C INPUT -p "$protocol" --dport "$port" -j ACCEPT &>/dev/null; do
                    sudo iptables -D INPUT -p "$protocol" --dport "$port" -j ACCEPT || break
                done
            done
            case "$backend" in
                ufw) sudo ufw --force delete allow "$port" &>/dev/null ;;
                firewalld) sudo firewall-cmd --permanent --remove-port="$port/tcp" --remove-port="$port/udp" &>/dev/null ;;
            esac
            echo "Firewall rules for port $port have been removed."
            log_action "Closed port $port"

            mapfile -t pids < <(_port_listeners "$port" | cut -f1 | sort -un)
            if ((${#pids[@]} > 0)); then
                echo "Processes listening on port $port:"
                _terminate_pids --sudo "${pids[@]}" && log_action "Terminated listeners on port $port"
            fi
        done
        if [[ "$backend" == firewalld ]]; then
            sudo firewall-cmd --reload
        fi
    }

    parse_arguments() {
        if (($# == 0)); then
            display_help
            return 1
        fi
        while (($# > 0)); do
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
                        port_number=${2-}
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

        if [[ -z $action ]]; then
            echo "Error: Action not specified."
            display_help
            return 1
        fi
    }

    main() {
        parse_arguments "$@" || return 1

        # Help exits successfully without requiring firewall tooling.
        [[ -n "$action" ]] || return 0
        check_dependencies || return 1

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
                port_manager_check
                log_action "Checked port(s) $port_number"
                ;;
            open) open_port ;;
            close) close_port ;;
        esac
    }

    main "$@"
)
