#!/usr/bin/env bash

# The config file is located at: https://github.com/slyfox1186/script-repo/blob/main/Bash/Arch%20Linux%20Scripts/pacman-mirror-update.conf

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script with root or sudo."
    exit 1
fi

# Function to display the help menu
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Update Pacman mirrorlist and create a systemd service to run periodically."
    echo
    echo "Options:"
    echo "  -f, --frequency <frequency>  Set the frequency of the service (default: weekly)"
    echo "                               Valid values: hourly, daily, weekly, monthly"
    echo "  -s, --service                Only run the code for creating the systemd service"
    echo "  -m, --mirrors <number>       Set the number of mirrors to test (default: 200)"
    echo "  -t, --top <number>           Set the number of top mirrors to save (default: 5)"
    echo "  -v, --verbose                Enable verbose output for the reflector command"
    echo "  -p, --protocol <protocol>    Set the protocol for the reflector command (default: https)"
    echo "                               Valid values: http, https, both"
    echo "  -l, --log <path>             Set the log file path (default: /var/log/pacman-mirror-update.log)"
    echo "  -e, --exclude <mirrors>      Exclude specific mirrors (comma-separated list)"
    echo "  -c, --country <code>         Set the country or region code for filtering mirrors"
    echo "  -d, --dry-run                Run the script in dry-run mode without making changes"
    echo "  --email <address>            Set the email address for notifications"
    echo "  --config <path>              Set the path to the configuration file"
    echo "  -h, --help                   Display this help menu"
    echo
    echo "Examples:"
    echo "  $0 -f daily -m 100 -t 10     Run the script, set the service frequency to daily, test 100 mirrors, and save the top 10"
    echo "  $0 -s -p http --dry-run      Only run the code for creating the systemd service, use HTTP protocol, and perform a dry run"
    echo "  $0 --config /path/to/config  Use the specified configuration file"
    echo "  $0 --help                    Display the help menu"
}

# Parse command-line arguments
config_file=""
frequency="weekly"
create_service_only=false
num_mirrors=200
top_mirrors=5
verbose=false
protocol="https"
log_file="/var/log/pacman-mirror-update.log"
country=
exclude_mirrors=
dry_run=false
email=""

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
        -t|--top)
            top_mirrors="$2"
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
        --email)
            email="$2"
            shift 2
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

# Read configuration file if it exists and was specified
if [[ -n "$config_file" ]]; then
    if [[ -f "$config_file" ]]; then
        while read -r line; do
            if [[ "$line" =~ ^[^#]*= ]]; then
                option_name="${line%%=*}"
                option_value="${line#*=}"
                option_value="${option_value%\"}"  # Remove trailing double quote
                option_value="${option_value#\"}"  # Remove leading double quote
                case "$option_name" in
                    frequency)
                        frequency="$option_value"
                        ;;
                    num_mirrors)
                        num_mirrors="$option_value"
                        ;;
                    top_mirrors)
                        top_mirrors="$option_value"
                        ;;
                    verbose)
                        if [[ "$option_value" == "true" ]]; then
                            verbose="true"
                        else
                            verbose="false"
                        fi
                        ;;
                    protocol)
                        protocol="$option_value"
                        ;;
                    log_file)
                        log_file="$option_value"
                        ;;
                    exclude_mirrors)
                        exclude_mirrors="$option_value"
                        ;;
                    country)
                        country="$option_value"
                        ;;
                    email)
                        email="$option_value"
                        ;;
                esac
            fi
        done < "$config_file"
    fi
fi

# Set the safe location for the script
script_location="/opt/pacman-mirror-update/update_mirrorlist.sh"

# Create the directory if it doesn't exist
mkdir -p "$(dirname "$script_location")"

# Copy the script to the safe location
cp "$0" "$script_location"

# Create the log file directory if it doesn't exist
log_dir="$(dirname "$log_file")"
mkdir -p "$log_dir"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}

if ! $create_service_only; then
    # Update the mirrorlist
    reflector_cmd="reflector --latest $num_mirrors --sort rate --save /etc/pacman.d/mirrorlist"

    if $verbose; then
        reflector_cmd+=" --verbose"
    fi

    if [[ "$protocol" != "both" ]]; then
        reflector_cmd+=" --protocol $protocol"
    fi

    if [[ -n "$exclude_mirrors" ]]; then
        reflector_cmd+=" --exclude $exclude_mirrors"
    fi

    if [[ -n "$country" ]]; then
        reflector_cmd+=" --country $country"
    fi

    if $dry_run; then
        log "Dry run: $reflector_cmd"
    else
        log "Updating mirrorlist..."
        eval "$reflector_cmd" 2>&1 | tee -a "$log_file"
        if [[ $? -ne 0 ]]; then
            log "No mirrors found. Exiting."
            exit 1
        else
            log "Mirrorlist updated successfully."

            if ! $dry_run; then
                # Backup the original mirrorlist
                cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
                log "Original mirrorlist backed up."

                # Get the top N fastest mirrors
                top_mirrors_list=$(sed -n "1,${top_mirrors}p" /etc/pacman.d/mirrorlist)

                # Create a new mirrorlist with only the top N mirrors
                echo "$top_mirrors_list" | tee /etc/pacman.d/mirrorlist.top >/dev/null

                # Move the updated mirrorlist to the original location
                mv /etc/pacman.d/mirrorlist.top /etc/pacman.d/mirrorlist
                log "Updated pacman mirrorlist with the top $top_mirrors fastest"
            fi
        fi
    fi
fi

if ! $dry_run; then
    # Create the systemd service file
    tee /etc/systemd/system/pacman-mirror-update.service >/dev/null <<EOF
[Unit]
Description=Update Pacman Mirrorlist
After=network.target

[Service]
Type=oneshot
ExecStart=$script_location

[Install]
WantedBy=multi-user.target
EOF

    # Create the systemd timer file
    tee /etc/systemd/system/pacman-mirror-update.timer >/dev/null <<EOF
[Unit]
Description=Run Pacman Mirror Update $frequency

[Timer]
OnCalendar=daily
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

log "Script execution completed."
