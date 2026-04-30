#!/usr/bin/env bash
# System Administration Functions

## GET THE OS AND ARCH OF THE ACTIVE COMPUTER ##
this_pc() {
    local OS VER
    source /etc/os-release
    OS="$NAME"
    VER="$VERSION_ID"

    echo "Operating System: $OS"
    echo "Specific Version: $VER"
    echo
}

# Clean OS
clean() {
    sudo apt -y autoremove
    sudo apt clean
    sudo apt autoclean
    sudo apt -y purge
}

# Update OS
update() {
    sudo apt update
    sudo apt -y full-upgrade
}

# Fix broken APT packages
fix() {
    [[ -f /tmp/apt.lock ]] && sudo rm /tmp/apt.lock
    sudo dpkg --configure -a
    sudo apt --fix-broken install
    sudo apt -f -y install
}

list() {
    local param
    if [[ -z "$1" ]]; then
        read -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    sudo apt list -- "*$param*" 2>/dev/null | awk -F'/' '{print $1}' | grep -Eiv '\-dev|Listing' | sort -fuV
}

listd() {
    local param
    if [[ -z "$1" ]]; then
        read -p "Enter the string to search: " param
    else
        param="$1"
    fi
    clear
    sudo apt list -- "*$param*-dev*" 2>/dev/null | awk -F'/' '{print $1}' | sort -fuV
}

# Use dpkg to search for all apt packages by passing a name to the function
dpkg_list() {
    local input="$1"
    
    if [[ -z "$input" ]]; then
        read -p "Enter the string to search: " input
    fi

    echo "Searching installed packages for: $input"
    dpkg -l | grep "$input"
}

dL() {
    local input="$1"
    
    if [[ -z "$input" ]]; then
        read -p "Enter the string to search: " input
    fi

    echo "Searching installed packages for: $input"
    dpkg -L "$input"
}

# Fix missing gpnu keys used to update packages
fix_key() {
    local file url

    if [[ -z "$1" ]] && [[ -z "$2" ]]; then
        read -p "Enter the filename to store in /etc/apt/trusted.gpg.d: " file
        read -p "Enter the gpg key url: " url
        clear
    else
        file="$1"
        url="$2"
    fi

    if curl -fsS# "$url" | gpg --dearmor | sudo tee "/etc/apt/trusted.gpg.d/$file"; then
        echo "The key was successfully added!"
    else
        echo "The key failed to add!"
    fi
}

# Download an APT package + all its dependencies in one go
dl_apt() {
    wget --show-progress -cq $(apt-get --print-uris -qq --reinstall install $1 2>/dev/null | cut -d"'" -f2)
    clear; ls -1AhFv --color --group-directories-first
}

# DPKG COMMANDS #

## Show all installed packages
showpkgs() {
    dpkg --get-selections | grep -v deinstall > "$HOME/tmp/packages.list"
    gnome-text-editor "$HOME/tmp/packages.list"
}

# Pipe all development packages names to file
save_apt_dev() {
    apt-cache search dev | grep '\-dev' | cut -d " " -f1 | sort > dev-packages.list
    gnome-text-editor dev-packages.list
}

## UNINSTALL DEBIAN FILES ##
rm_deb() {
    local fname

    if [[ -n "$1" ]]; then
        sudo dpkg -r "$(dpkg -f "$1" Package)"
    else
        read -p "Please enter the Debian FILE name: " fname
        clear
        sudo dpkg -r "$(dpkg -f "$fname" Package)"
    fi
}

## LIST INSTALLED PACKAGES BY ORDER OF IMPORTANCE
list_pkgs() {
    dpkg-query -Wf '${Package;-40}${Priority}\n' | sort -b -k2,2 -k1,1
}

## Show NVME temperature ##
nvme_temp() {
    local n0 n1 n2

    [[ -d "/dev/nvme0n1" ]] && n0=$(sudo nvme smart-log /dev/nvme0n1)
    [[ -d "/dev/nvme1n1" ]] && n1=$(sudo nvme smart-log /dev/nvme0n1)
    [[ -d "/dev/nvme2n1" ]] && n2=$(sudo nvme smart-log /dev/nvme0n1)
    echo -e "nvme0n1: $n0\nnvme1n1: $n1\nnvme2n1: $n2"
}

## Write caching ##
wcache() {
    local choice

    lsblk
    echo
    read -p "Enter the drive id to turn off write caching (/dev/sdX w/o /dev/): " choice

    sudo hdparm -W 0 /dev/"$choice"
}

## CHANGE HOSTNAME OF PC ##
chostname() {
    local name
    clear

    if [[ -z "$1" ]]; then
        read -p "Please enter the new hostname: " name
    else
        name="$1"
    fi

    sudo nmcli g hostname "$name"
    clear
    printf "%s\n\n" "The new hostname is listed below."
    hostname
}

# Mount Network Drive
mnd() {
    local drive_ip="192.168.2.2" drive_name="Cloud" mount_point="m"

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
    read -p "Enter your choice (1/2): " user_choice

    case $user_choice in
        1) mount_drive ;;
        2) unmount_drive ;;
        *) echo "Invalid choice. Please enter 1 or 2." ;;
    esac
}

# Get current time
st() {
    date +%r | cut -d " " -f1-2 | grep -E "^.*$"
}

## LIST PPA REPOS
list_ppa() {
    local entry host user ppa

    for apt in $(find /etc/apt/ -type f -name \*.list); do
        grep -Po "(?<=^deb\s).*?(?=#|$)" "$apt" | while read -r entry; do
            host=$(echo "$entry" | cut -d/ -f3)
            user=$(echo "$entry" | cut -d/ -f4)
            ppa=$(echo "$entry" | cut -d/ -f5)
            if [[ "ppa.launchpad.net" = "$host" ]]; then
                echo sudo apt-add-repository ppa:"$user/$ppa"
            else
                echo sudo apt-add-repository \"deb "$entry"\"
            fi
        done
    done
}

# CUDA commands
cuda_purge() {
    local choice

    echo "Do you want to completely remove the cuda-sdk-toolkit?"
    echo "WARNING: Do not reboot your PC without reinstalling the nvidia-driver first!"
    echo "[1] Yes"
    echo "[2] Exit"
    echo
    read -p "Your choices are (1 or 2): " choice
    clear

    if [[ $choice -eq 1 ]]; then
        echo "Purging the CUDA-SDK-Toolkit from your PC"
        echo "================================================"
        echo
        sudo apt -y --purge remove "*cublas*" "cuda*" "nsight*"
        sudo apt -y autoremove
        sudo apt update
    else
        return 0
    fi
}

# Check Port Numbers
check_port() {
    local port="${1:-$(read -p 'Enter the port number: ' port && echo "$port")}"
    local -A pid_protocol_map pid name protocol choice process_found=false

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
            read -p "Kill it? (yes/no): " choice
        else
            read -p "Kill this process? (yes/no): " choice
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

# Port Manager
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

myip() {
    echo "LAN: $(ip route get 1.2.3.4 | awk '{print $7}')"
    echo "WAN: $(curl -fsS "https://checkip.amazonaws.com")"
}

# Domain Lookup
dlu() {
    local domain_list=("${@:-$(read -p "Enter the domain(s) to pass: " -a domain_list && echo "${domain_list[@]}")}")

    if [[ ! -f /usr/local/bin/domain_lookup.py ]]; then
        sudo wget -cqO /usr/local/bin/domain_lookup.py "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/domain_lookup.py"
        sudo chmod +x /usr/local/bin/domain_lookup.py
    fi
        python3 /usr/local/bin/domain_lookup.py "${domain_list[@]}"
}