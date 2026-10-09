#!/usr/bin/env bash
# Networking and Download Functions

## ARIA2 COMMANDS ##

# Aria2 daemon in the background
aria2_on() {
    if aria2c --conf-path="$HOME/.aria2/aria2.conf"; then
        echo
        echo "Command Executed Successfully"
    else
        echo
        echo "Command Failed"
    fi
}

# Stop aria2 daemon
aria2_off() {
    clear
    killall aria2c
}

myip() {
    echo "LAN: $(ip route get 1.2.3.4 | awk '{print $7}')"
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

adl() {
local file url

if [[ "$#" -ne 2 ]]; then
    echo "Error: Two arguments are required: output file and download URL"
    return 1
fi

if ! command -v aria2c &>/dev/null; then
    echo "aria2c is missing and will be installed."
    sleep 3
    bash <(curl -fsSL "https://aria2.optimizethis.net")
fi

file="$1"

# Check if the file extension is missing and append '.mp4' if needed
if [[ "$file" != *.mp4 ]]; then
    file+=".mp4"
fi

url="$2"

if [[ ! -f "$HOME/.aria2/aria2.conf" ]]; then
    mkdir -p "$HOME/.aria2"
    if ! wget -cqO "/tmp/create-aria2-folder.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/Networking/create-aria2-folder.sh"; then
        echo "Failed to download the aria2.conf installer script."
        return 1
    fi
    if ! bash "/tmp/create-aria2-folder.sh"; then
        echo "Failed to execute: /tmp/create-aria2-folder.sh"
        return 1
    fi
fi
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

# Aria2c batch downloader
adt() {
    local json_script="add-video-to-json.py"
    local run_script="batch-downloader.py"
    local repo_base="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/aria2"

    # Check and download Python scripts if they don't exist
    for script in "$json_script" "$run_script"; do
        if [ ! -f "$script" ]; then
            echo "Downloading $script from GitHub..."
            if ! wget --show-progress -cqO "$script" "$repo_base/$script"; then
                echo "Error: Failed to download $script from GitHub." >&2
                return 1
            fi
            echo "$script downloaded successfully."
        fi
    done

    # Prompt for video details
    echo "Enter the video details:"
    read -r -p "Filename: " filename
    read -r -p "Extension: " extension
    read -r -p "Path: " path
    read -r -p "URL: " url

    # Validate input
    if [[ -z "$filename" || -z "$extension" || -z "$path" || -z "$url" ]]; then
        echo "Error: All fields are required." >&2
        return 1
    fi

    # Call the Python script with the provided arguments
    echo "Adding video details to JSON file..."
    if ! output=$(python3 "$json_script" "$filename" "$extension" "$path" "$url" 2>&1); then
        echo "Error: Failed to add video details." >&2
        echo "Python script error output:" >&2
        echo "$output" >&2
        return 1
    fi
    echo "Video details added successfully:"
    echo "$output"

    # Check for '--run' argument before executing batch downloader
    if [[ "$1" == "--run" ]]; then
        echo "Starting batch download..."
        python3 "$run_script"
    else
        echo "Batch download not initiated. Pass '--run' to start downloading."
    fi
}

# Domain Lookup
dlu() {
    local domain_list=("${@:-$(read -r -p "Enter the domain(s) to pass: " -a domain_list && echo "${domain_list[@]}")}")

    if [[ ! -f /usr/local/bin/domain_lookup.py ]]; then
        sudo wget -cqO /usr/local/bin/domain_lookup.py "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/domain_lookup.py"
        sudo chmod +x /usr/local/bin/domain_lookup.py
    fi
        python3 /usr/local/bin/domain_lookup.py "${domain_list[@]}"
}

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

port_manager() (
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
        sudo ss -tuln | grep LISTEN | awk '{print $5}' | cut -d: -f2 | sort -n | uniq | while read -r port; do
            echo "  $port"
        done
        echo

        echo "Firewall rules (allowed incoming):"
        echo

        # Check iptables
        echo "iptables rules:"
        sudo iptables -L INPUT -n | awk '$1=="ACCEPT" {print $0}' |
            grep -oP 'dpt:\K\d+' | sort -n | uniq | while read -r port; do
            echo "  $port (iptables)"
        done
        echo

        # Check UFW if available
        if command -v ufw &>/dev/null; then
            echo "UFW rules:"
            sudo ufw status | grep ALLOW | awk '{print $1}' | sort -n | uniq | while read -r port; do
                echo "  $port (UFW)"
            done
            echo
        fi

        # Check firewalld if available
        if command -v firewall-cmd &>/dev/null; then
            echo "firewalld rules:"
            sudo firewall-cmd --list-ports | tr ' ' '\n' | sort -n | uniq | while read -r port; do
                echo "  $port (firewalld)"
            done
            echo
        fi
    }

    # Check if specific ports are open or allowed in the firewall
    port_manager_check() {
        if [[ -z "$port_number" ]]; then
            echo "Error: Port number(s) not specified."
            display_help
            return 1
        fi

        IFS=',' read -r -ra ADDR <<< "$port_number"
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
                IFS='-' read -r -ra RANGE <<< "$port"
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

        IFS=',' read -r -ra ADDR <<< "$port_number"
        for port in "${ADDR[@]}"; do
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                if $verbose; then echo "Opening port $port in the firewall..."; fi
                sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
                sudo iptables -A INPUT -p udp --dport "$port" -j ACCEPT
                echo "Port $port has been allowed in the firewall."
                log_action "Opened port $port"
            elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -r -ra RANGE <<< "$port"
                for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                    if $verbose; then echo "Opening port $i in the firewall..."; fi
                    sudo iptables -A INPUT -p tcp --dport "$i" -j ACCEPT
                    sudo iptables -A INPUT -p udp --dport "$i" -j ACCEPT
                    echo "Port $i has been allowed in the firewall."
                    log_action "Opened port $i"
                done
            else
                echo "Invalid port or range: $port"
            fi
        done

        # Check for firewall and prompt user
        if command -v ufw &>/dev/null; then
            read -r -p "Would you like to add these ports to the UFW firewall whitelist? (y/n): " choice
            if [[ "$choice" == "y" ]]; then
                for port in "${ADDR[@]}"; do
                    if [[ "$port" =~ ^[0-9]+$ ]]; then
                        sudo ufw allow "$port"
                        log_action "Added port $port to UFW"
                    elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                        IFS='-' read -r -ra RANGE <<< "$port"
                        for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                            sudo ufw allow "$i"
                            log_action "Added port $i to UFW"
                        done
                    fi
                done
                echo "Attempting to restart the firewall. This may take a moment..."
                sudo ufw reload
            fi
        elif command -v firewall-cmd &>/dev/null; then
            read -r -p "Would you like to add these ports to the firewalld whitelist? (y/n): " choice
            if [[ "$choice" == "y" ]]; then
                for port in "${ADDR[@]}"; do
                    if [[ "$port" =~ ^[0-9]+$ ]]; then
                        sudo firewall-cmd --permanent --add-port="$port/tcp"
                        sudo firewall-cmd --permanent --add-port="$port/udp"
                        log_action "Added port $port to firewalld"
                    elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                        IFS='-' read -r -ra RANGE <<< "$port"
                        for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                            sudo firewall-cmd --permanent --add-port="$i/tcp"
                            sudo firewall-cmd --permanent --add-port="$i/udp"
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

        IFS=',' read -r -ra ADDR <<< "$port_number"
        for port in "${ADDR[@]}"; do
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                read -r -p "Are you sure you want to close port $port? (y/n): " confirm
                if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                    if $verbose; then echo "Closing port $port..."; fi
                    sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT
                    sudo iptables -D INPUT -p udp --dport "$port" -j ACCEPT
                    echo "Firewall rule for port $port has been removed."
                    log_action "Closed port $port"

                    local -a pids=()
                    mapfile -t pids < <(sudo lsof -t -i:"$port")
                    if ((${#pids[@]} > 0)); then
                        read -r -p "Process PID(s) ${pids[*]} use port $port. Terminate them? (y/n): " terminate
                        if [[ $terminate == [yY] || $terminate == [yY][eE][sS] ]]; then
                            if $verbose; then echo "Terminating process PID(s) ${pids[*]} using port $port..."; fi
                            if sudo kill -9 "${pids[@]}"; then
                                echo "Process using port $port has been terminated."
                                log_action "Terminated process PID(s) ${pids[*]} using port $port"
                            else
                                echo "Error: Failed to terminate the process using port $port."
                            fi
                        fi
                    fi
                fi
            elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -r -ra RANGE <<< "$port"
                read -r -p "Are you sure you want to close ports ${RANGE[0]}-${RANGE[1]}? (y/n): " confirm
                if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                    for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                        if $verbose; then echo "Closing port $i..."; fi
                        sudo iptables -D INPUT -p tcp --dport "$i" -j ACCEPT
                        sudo iptables -D INPUT -p udp --dport "$i" -j ACCEPT
                        echo "Firewall rule for port $i has been removed."
                        log_action "Closed port $i"

                        local -a pids=()
                        mapfile -t pids < <(sudo lsof -t -i:"$i")
                        if ((${#pids[@]} > 0)); then
                            read -r -p "Process PID(s) ${pids[*]} use port $i. Terminate them? (y/n): " terminate
                            if [[ $terminate == [yY] || $terminate == [yY][eE][sS] ]]; then
                                if $verbose; then echo "Terminating process PID(s) ${pids[*]} using port $i..."; fi
                                if sudo kill -9 "${pids[@]}"; then
                                    echo "Process using port $i has been terminated."
                                    log_action "Terminated process PID(s) ${pids[*]} using port $i"
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
                    sudo ufw delete allow "$port"
                    log_action "Removed port $port from UFW"
                elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                    IFS='-' read -r -ra RANGE <<< "$port"
                    for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                        sudo ufw delete allow "$i"
                        log_action "Removed port $i from UFW"
                    done
                fi
            done
            echo "Attempting to restart the firewall. This may take a moment..."
            sudo ufw reload
        elif command -v firewall-cmd &>/dev/null; then
            for port in "${ADDR[@]}"; do
                if [[ "$port" =~ ^[0-9]+$ ]]; then
                    sudo firewall-cmd --permanent --remove-port="$port/tcp"
                    sudo firewall-cmd --permanent --remove-port="$port/udp"
                    log_action "Removed port $port from firewalld"
                elif [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; then
                    IFS='-' read -r -ra RANGE <<< "$port"
                    for ((i=RANGE[0]; i<=RANGE[1]; i++)); do
                        sudo firewall-cmd --permanent --remove-port="$i/tcp"
                        sudo firewall-cmd --permanent --remove-port="$i/udp"
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
        if ! parse_arguments "$@"; then
            return 1
        fi

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
)

# Mount Network Drive
mnd() (
    local drive_ip="192.168.2.2" drive_name="Cloud" mount_point="m"
    local user_choice

    is_mounted() {
        mountpoint -q "/$mount_point"
    }

    mount_drive() {
        if is_mounted; then
            echo "Drive '$drive_name' is already mounted at $mount_point."
        else
            mkdir -p "/$mount_point"
            mount -t drvfs "\\\\$drive_ip\\$drive_name" "/$mount_point" &&
                echo "Drive '$drive_name' mounted successfully at $mount_point."
        fi
    }

    unmount_drive() {
        if is_mounted; then
            umount "/$mount_point" &&
                echo "Drive '$drive_name' unmounted successfully from $mount_point."
        else
            echo "Drive '$drive_name' is not mounted."
        fi
    }

    echo "Select an option:"
    echo "1) Mount the network drive"
    echo "2) Unmount the network drive"
    read -r -p "Enter your choice (1/2): " user_choice

    case $user_choice in
        1) mount_drive ;;
        2) unmount_drive ;;
        *) echo "Invalid choice. Please enter 1 or 2." ;;
    esac
)
