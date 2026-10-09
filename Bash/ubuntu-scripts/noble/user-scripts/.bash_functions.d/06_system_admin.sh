#!/usr/bin/env bash
# System Administration Functions

## GET THE OS AND ARCH OF THE ACTIVE COMPUTER ##
this_pc() {
    local os version
    # shellcheck source=/etc/os-release
    source /etc/os-release
    os="${NAME:-Unknown}"
    version="${VERSION_ID:-Unknown}"

    printf 'Operating System: %s\n' "$os"
    printf 'Specific Version: %s\n' "$version"
    echo
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
    read -r -p "Enter the drive id to turn off write caching (/dev/sdX w/o /dev/): " choice

    sudo hdparm -W 0 /dev/"$choice"
}

###########################
## CHANGE HOSTNAME OF PC ##
###########################

chostname() {
    local name
    clear

    if [[ -z "$1" ]]; then
        read -r -p "Please enter the new hostname: " name
    else
        name="$1"
    fi

    sudo nmcli g hostname "$name"
    clear
    printf "%s\n\n" "The new hostname is listed below."
    hostname
}

# A collection of bash functions to simplify finding, stopping, and starting systemd services.

# --- FIND SERVICE ---
# Searches for a systemd service by keyword(s).
# Usage: find_service <keyword1> [keyword2] ...
find_service() {
    if [[ $# -eq 0 ]]; then
        echo "Error: Please provide at least one search term." >&2
        echo "Usage: find_service <keyword1> [keyword2] ..." >&2
        return 1
    fi
    # Use '|' as an OR operator for grep to find any of the keywords
    local IFS='|'
    sudo systemctl list-units --type=service --all | grep -E --color=always "$*"
}

# --- KILL SERVICE ---
# Stops and optionally disables one or more systemd services.
# Usage: kill_service [-d] service1.service [service2.service ...]
kill_service() {
    local disable=false opt
    local error_occurred=false
    local OPTIND=1

    # --- Argument Parsing ---
    while getopts "d" opt; do
        case $opt in
            d) disable=true ;;
            *)
                echo "Error: Invalid option -$OPTARG" >&2
                echo "Usage: kill_service [-d] service1.service [service2.service ...]" >&2
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    if [ $# -eq 0 ]; then
        echo "Error: No service names provided." >&2
        echo "Usage: kill_service [-d] service1.service [service2.service ...]" >&2
        return 1
    fi

    local stopped_count=0
    local disabled_count=0
    local services_processed=0

    # --- Service Processing Loop ---
    for service in "$@"; do
        services_processed=$((services_processed + 1))
        echo "--- Processing '$service' ---"

        # 1. Check if the service unit file exists
        if ! sudo systemctl list-unit-files | grep -q "^$service"; then
            echo "Warning: Service '$service' does not exist. Skipping."
            continue
        fi

        # 2. Stop the service if it's active
        if sudo systemctl is-active --quiet "$service"; then
            echo "Stopping service..."
            if sudo systemctl stop "$service"; then
                echo "Successfully stopped."
                stopped_count=$((stopped_count + 1))
            else
                echo "Error: Failed to stop '$service'." >&2
                error_occurred=true
            fi
        else
            echo "Service is already inactive."
        fi

        # 3. Disable the service if -d flag was passed
        if [ "$disable" = true ]; then
            if sudo systemctl is-enabled --quiet "$service"; then
                echo "Disabling service..."
                if sudo systemctl disable "$service"; then
                    echo "Successfully disabled."
                    disabled_count=$((disabled_count + 1))
                else
                    echo "Error: Failed to disable '$service'." >&2
                    error_occurred=true
                fi
            else
                echo "Service is already disabled."
            fi
        fi
    done

    # --- Final Summary ---
    echo "========================================"
    echo "Task Complete. Processed $services_processed service(s)."
    echo "Confirmation: Successfully stopped $stopped_count service(s)."

    if [ "$disable" = true ]; then
        echo "Confirmation: Successfully disabled $disabled_count service(s)."
    fi

    if [ "$error_occurred" = true ]; then
        echo "Warning: One or more errors occurred during the operation."
        return 1
    fi
}

# --- START SERVICE HELPER ---
# Helper function to display usage and best practices for start_service.
_start_service_usage() {
    echo "The 'start_service' command helps you activate and enable systemd services."
    echo ""
    echo "Usage: start_service [-s] [-e] [-h] service1.service [service2.service ...]"
    echo ""
    echo "Arguments:"
    echo "  -s         Start the service(s) for the current session."
    echo "  -e         Enable the service(s) to start automatically on boot."
    echo "  -h         Display this help menu."
    echo ""
    echo "--- Best Practices ---"
    echo "1. Start vs. Enable: What's the difference?"
    echo "   - 'Starting' a service (-s) runs it right now, but it won't restart after a reboot."
    echo "   - 'Enabling' a service (-e) tells the system to run it on the next boot, but it doesn't start it now."
    echo ""
    echo "2. The Most Common Use Case (Do Both):"
    echo "   To make a service persistent and run it immediately, use both flags: 'start_service -e -s your.service'"
    echo "   This is the equivalent of the powerful 'systemctl enable --now' command."
    echo ""
    echo "3. Check Your Work:"
    echo "   You can always verify a service's status with: 'systemctl status your.service'"
    echo "   The command will show if the service is 'active (running)' and 'enabled'."
    echo ""
    echo "4. Idempotency (It's Safe to Re-run):"
    echo "   This script won't cause errors if a service is already active or enabled. It will simply"
    echo "   report the current state, so you can run it without worrying about breaking things."
}

# --- START SERVICE ---
# Starts and optionally enables one or more systemd services.
# Usage: start_service [-s] [-e] [-h] service1.service [service2.service ...]
start_service() {
    local start=false opt
    local enable=false
    local show_help=false
    local error_occurred=false
    local OPTIND=1

    # --- Argument Parsing ---
    while getopts ":seh" opt; do
        case $opt in
            s) start=true ;;
            e) enable=true ;;
            h) show_help=true ;;
            \?) echo "Error: Invalid option -$OPTARG" >&2
                _start_service_usage
                return 1
                ;;
        esac
    done

    # If -h was passed, show the help menu and exit immediately.
    if [ "$show_help" = true ]; then
        _start_service_usage
        return 0
    fi

    shift $((OPTIND - 1))

    # --- Argument Validation ---
    if [ $# -eq 0 ]; then
        echo "Error: No service names provided." >&2
        _start_service_usage
        return 1
    fi

    # Check if no action flags were provided.
    if [[ "$start" = false && "$enable" = false ]]; then
        echo "No action flags (-s or -e) provided. Nothing to do." >&2
        _start_service_usage
        return 1
    fi

    local started_count=0
    local enabled_count=0
    local services_processed=0

    # --- Service Processing Loop ---
    for service in "$@"; do
        services_processed=$((services_processed + 1))
        echo "--- Processing '$service' ---"

        # 1. Check if the service unit file exists
        if ! sudo systemctl list-unit-files | grep -q "^$service"; then
            echo "Warning: Service '$service' does not exist. Skipping."
            continue
        fi

        # 2. Start the service if -s was passed and it's not already active
        if [ "$start" = true ]; then
            if ! sudo systemctl is-active --quiet "$service"; then
                echo "Starting service..."
                if sudo systemctl start "$service"; then
                    echo "Successfully started."
                    started_count=$((started_count + 1))
                else
                    echo "Error: Failed to start '$service'." >&2
                    error_occurred=true
                fi
            else
                echo "Service is already active."
            fi
        fi

        # 3. Enable the service if -e was passed and it's not already enabled
        if [ "$enable" = true ]; then
            if ! sudo systemctl is-enabled --quiet "$service"; then
                echo "Enabling service..."
                if sudo systemctl enable "$service"; then
                    echo "Successfully enabled."
                    enabled_count=$((enabled_count + 1))
                else
                    echo "Error: Failed to enable '$service'." >&2
                    error_occurred=true
                fi
            else
                echo "Service is already enabled."
            fi
        fi
    done

    # --- Final Summary ---
    echo "========================================"
    echo "Task Complete. Processed $services_processed service(s)."

    if [ "$start" = true ]; then
        echo "Started $started_count service(s)."
    fi
    if [ "$enable" = true ]; then
        echo "Enabled $enabled_count service(s)."
    fi

    if [ "$error_occurred" = true ]; then
        echo "Warning: One or more errors occurred during the operation."
        return 1
    fi
    return 0
}

############
## DOCKER ##
############

drp() {
    local choice restart_policy
    clear

    printf "%s\n\n%s\n%s\n%s\n%s\n\n" \
        "Change the Docker restart policy" \
        "[1] Restart Always" \
        "[2] Restart Unless Stopped " \
        "[3] On Failure" \
        "[4] No"
    read -r -p "Your choices are (1 to 4): " choice
    clear

    case "$choice" in
        1)      restart_policy="always" ;;
        2)      restart_policy="unless-stopped" ;;
        3)      restart_policy="on-failure" ;;
        4)      restart_policy="no" ;;
        *)
                clear
                printf "%s\n\n" "Bad user input. Please try again..."
                return 1
                ;;
    esac

    docker update --restart="${restart_policy}"
}
