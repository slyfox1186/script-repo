#!/usr/bin/env bash
# Example config file = https://github.com/slyfox1186/script-repo/blob/main/Bash/Arch%20Linux%20Scripts/pacman-mirror-update.conf

#######################################
# Description: Update Pacman mirrorlist and create a systemd service to run periodically.
# Author: Your Name
# Date: Current Date
# Version: 1.0
# Usage: ./update_mirrorlist.sh [OPTIONS]
# Options:
#   -h, --help                   Display the help menu
#   -c, --country <code>         Set the country or region code for filtering mirrors
#   --config <path>              Set the path to the configuration file
#   -d, --dry-run                Run the script in dry-run mode without making changes
#   -e, --exclude <mirrors>      Exclude specific mirrors (comma-separated list)
#   -f, --frequency <frequency>  Set the frequency of the service (default: weekly)
#                                Valid values: hourly, daily, weekly, monthly
#   -l, --log <path>             Set the log file path (default: /var/log/pacman-mirror-update.log)
#   -m, --mirrors <number>       Set the number of mirrors to test (default: 200)
#   -p, --protocol <protocol>    Set the protocol for the reflector command (default: https)
#                                Valid values: http, https, both
#   -s, --service                Only run the code for creating the systemd service
#   -v, --verbose                Enable verbose output for the reflector command
# Note: This script requires root or sudo privileges to run.
#######################################

# Declare variables as readonly
readonly script_name="update_mirrorlist.sh"
readonly script_version="1.0"
readonly default_log_file="/var/log/pacman-mirror-update.log"
readonly default_num_mirrors=200
readonly default_protocol="https"
readonly default_frequency="weekly"

# Function to display the help menu
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Update Pacman mirrorlist and create a systemd service to run periodically."
    echo
    echo "Options:"
    echo "  -h, --help                   Display this help menu"
    echo "  -c, --country <code>         Set the country or region code for filtering mirrors"
    echo "  --config <path>              Set the path to the configuration file"
    echo "  -d, --dry-run                Run the script in dry-run mode without making changes"
    echo "  -e, --exclude <mirrors>      Exclude specific mirrors (comma-separated list)"
    echo "  -f, --frequency <frequency>  Set the frequency of the service (default: weekly)"
    echo "                               Valid values: hourly, daily, weekly, monthly"
    echo "  -l, --log <path>             Set the log file path (default: /var/log/pacman-mirror-update.log)"
    echo "  -m, --mirrors <number>       Set the number of mirrors to test (default: 200)"
    echo "  -p, --protocol <protocol>    Set the protocol for the reflector command (default: https)"
    echo "                               Valid values: http, https, both"
    echo "  -s, --service                Only run the code for creating the systemd service"
    echo "  -v, --verbose                Enable verbose output for the reflector command"
    echo
    echo "Examples:"
    echo "  $0 -f daily -m 100           Run the script, set the service frequency to daily, test 100 mirrors"
    echo "  $0 -s -p http --dry-run      Only run the code for creating the systemd service, use HTTP protocol, and perform a dry run"
    echo "  $0 --config /path/to/config  Use the specified configuration file"
    echo "  $0 --help                    Display the help menu"
}

# Parse command-line arguments
config_file=""
country=""
create_service_only="false"
dry_run="false"
exclude_mirrors=""
frequency="$default_frequency"
log_file="$default_log_file"
num_mirrors=$default_num_mirrors
protocol="$default_protocol"
verbose="false"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -f|--frequency)
            frequency="$2"
            shift 2
            ;;
        -s|--service)
            create_service_only=true
            shift
            ;;
        -m|--mirrors)
            num_mirrors="$2"
            shift 2
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -p|--protocol)
            protocol="$2"
            shift 2
            ;;
        -l|--log)
            log_file="$2"
            shift 2
            ;;
        -e|--exclude)
            exclude_mirrors="$2"
            shift 2
            ;;
        -c|--country)
            country="$2"
            shift 2
            ;;
        -d|--dry-run)
            dry_run=true
            shift
            ;;
        --config)
            config_file="$2"
            shift 2
            ;;
        -h|--help)
            display_help
            exit 0
            ;;
        *)
            echo "Invalid option: $1" >&2
            display_help
            exit 1
            ;;
    esac
done

# Check if the specified configuration file exists
if [[ -n "$config_file" ]]; then
    if [[ ! -f "$config_file" ]]; then
        echo "Error: The specified configuration file '$config_file' does not exist." >&2
        exit 1
    fi
fi

# Read configuration file if it exists and was specified
if [[ -n "$config_file" ]]; then
    while IFS='=' read -r key value; do
        case "$key" in
            "frequency") frequency="$value" ;;
            "num_mirrors") num_mirrors="$value" ;;
            "verbose") verbose="$value" ;;
            "protocol") protocol="$value" ;;
            "log_file") log_file="$value" ;;
            "exclude_mirrors") exclude_mirrors="$value" ;;
            "country") country="$value" ;;
        esac
    done < "$config_file"
fi

# Validate user input
if [[ "$num_mirrors" -lt 1 ]]; then
    echo "Error: Number of mirrors must be a positive integer." >&2
    exit 1
fi

if [[ "$protocol" != "http" && "$protocol" != "https" && "$protocol" != "both" ]]; then
    echo "Error: Invalid protocol. Allowed values are 'http', 'https', or 'both'." >&2
    exit 1
fi

if [[ "$frequency" != "hourly" && "$frequency" != "daily" && "$frequency" != "weekly" && "$frequency" != "monthly" ]]; then
    echo "Error: Invalid frequency. Allowed values are 'hourly', 'daily', 'weekly', or 'monthly'." >&2
    exit 1
fi

# Set the safe location for the script
readonly script_location="/opt/pacman-mirror-update/update_mirrorlist.sh"

# Create the log file directory if it doesn't exist
log_dir="$(dirname "$log_file")"
mkdir -p "$log_dir"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}

if ! "$create_service_only"; then
    # Backup the original mirrorlist
    if [[ ! -f /etc/pacman.d/mirrorlist.backup ]]; then
        cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
        log "Original mirrorlist backed up."
    else
        cp -f /etc/pacman.d/mirrorlist.backup /etc/pacman.d/mirrorlist
        log "Backup mirrorlist has overwritten the input mirror list to ensure the list is complete and ready to be ranked."
    fi
    # Update the mirrorlist
    reflector_cmd=(
        reflector
        --latest "$num_mirrors"
        --sort rate
        --save /etc/pacman.d/mirrorlist.new
    )

    if "$verbose"; then
        reflector_cmd+=(--verbose)
    fi

    if [[ "$protocol" != "both" ]]; then
        reflector_cmd+=(--protocol "$protocol")
    fi

    if [[ -n "$exclude_mirrors" ]]; then
        reflector_cmd+=(--exclude "$exclude_mirrors")
    fi

    if [[ -n "$country" ]]; then
        reflector_cmd+=(--country "$country")
    fi

    if "$dry_run"; then
        log "Dry run: ${reflector_cmd[*]}"
    else
        log "Updating mirrorlist..."
        if ! "${reflector_cmd[@]}" 2>&1 | tee -a "$log_file"; then
            log "No mirrors found. Exiting."
            exit 1
        else
            log "Mirrorlist updated successfully."

            if ! "$dry_run"; then
                # Get the list of selected mirrors
                selected_mirrors=$(awk '/^Server/ {print $3}' /etc/pacman.d/mirrorlist.new)

                # Create a temporary file to store the updated mirrorlist
                temp_mirrorlist=$(mktemp)

                # Add a separator line
                echo "################################################################################" > "$temp_mirrorlist"
                echo "################# Arch Linux mirrorlist generated by Reflector #################" >> "$temp_mirrorlist"
                echo "################################################################################" >> "$temp_mirrorlist"
                echo  >> "$temp_mirrorlist"

                # Add the selected mirrors to the temporary mirrorlist
                while IFS= read -r mirror; do
                    echo "Server = $mirror" >> "$temp_mirrorlist"
                done <<< "$selected_mirrors"
                echo  >> "$temp_mirrorlist"

                # Append the remaining mirrors as commented out, excluding the selected mirrors
                sed -n '/^#Server/p' /etc/pacman.d/mirrorlist | while IFS= read -r line; do
                    if ! echo "$selected_mirrors" | grep -q "$(echo "$line" | cut -d'=' -f2 | tr -d '[:space:]')"; then
                        echo "$line" >> "$temp_mirrorlist"
                    fi
                done

                # Replace the original mirrorlist with the updated mirrorlist
                mv "$temp_mirrorlist" /etc/pacman.d/mirrorlist

                # Remove the temporary mirrorlist files
                rm -f /etc/pacman.d/mirrorlist.new

                log "Updated pacman mirrorlist with the top $num_mirrors fastest mirrors"
            fi
        fi
    fi
fi

if "$create_service_only"; then
    # Create the directory if it doesn't exist
    mkdir -p "$(dirname "$script_location")"

    # Copy the script to the safe location
    cp -f "$0" "$script_location"

    if ! "$dry_run"; then
        # Create the systemd service file
        tee /etc/systemd/system/pacman-mirror-update.service >/dev/null <<EOF
[Unit]
Description=Update Pacman Mirrorlist
After=network.target

[Service]
Type=oneshot
ExecStart=$script_location -m $num_mirrors -p $protocol -l $log_file -f $frequency $(if [[ -n $exclude_mirrors ]]; then echo "-e $exclude_mirrors"; fi) $(if [[ -n $country ]]; then echo "-c $country"; fi) $(if "$verbose"; then echo "-v"; fi)

[Install]
WantedBy=multi-user.target
EOF

        # Create the systemd timer file
        tee /etc/systemd/system/pacman-mirror-update.timer >/dev/null <<EOF
[Unit]
Description=Run Pacman Mirror Update $frequency

[Timer]
OnCalendar=$frequency
Persistent=true

[Install]
WantedBy=timers.target
EOF

        # Reload the systemd configuration
        systemctl daemon-reload

        # Enable and start the timer
        systemctl enable --now pacman-mirror-update.timer
        log "Created and enabled the pacman-mirror-update service and timer with frequency: $frequency"
    else
        log "Dry run: Skipping creation of systemd service and timer."
    fi
fi
