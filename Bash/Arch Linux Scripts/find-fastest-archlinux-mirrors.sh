#!/usr/bin/env bash

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
  echo "  -v, --verbose                Enable verbose output for the reflector command"
  echo "  -p, --protocol <protocol>    Set the protocol for the reflector command (default: https)"
  echo "                               Valid values: http, https, both"
  echo "  -h, --help                   Display this help menu"
  echo
  echo "Examples:"
  echo "  $0 -f daily -m 100           Run the script, set the service frequency to daily, and test 100 mirrors"
  echo "  $0 -s -p http                Only run the code for creating the systemd service and use HTTP protocol"
  echo "  $0 --help                    Display the help menu"
}

# Parse command-line arguments
frequency="weekly"
create_service_only=false
num_mirrors=200
verbose=false
protocol="https"

while [[ $# -gt 0 ]]; do
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

# Set the safe location for the script
script_location="/opt/pacman-mirror-update/update_mirrorlist.sh"

# Create the directory if it doesn't exist
mkdir -p "$(dirname "$script_location")"

# Copy the script to the safe location
cp "$0" "$script_location"

if ! $create_service_only; then
  # Update the mirrorlist
  reflector_cmd="reflector --latest $num_mirrors --sort rate --save /etc/pacman.d/mirrorlist"
  
  if $verbose; then
    reflector_cmd+=" --verbose"
  fi
  
  if [[ "$protocol" != "both" ]]; then
    reflector_cmd+=" --protocol $protocol"
  fi
  
  eval "$reflector_cmd"

  # Backup the original mirrorlist
  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

  # Get the top 5 fastest mirrors
  top_mirrors=$(sed -n '1,5p' /etc/pacman.d/mirrorlist)

  # Create a new mirrorlist with only the top 5 mirrors
  echo "$top_mirrors" | tee /etc/pacman.d/mirrorlist > /dev/null

  echo "Updated pacman mirrorlist with the top 5 fastest mirrors."
fi

# Create the systemd service file
tee /etc/systemd/system/pacman-mirror-update.service > /dev/null <<EOF
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
tee /etc/systemd/system/pacman-mirror-update.timer > /dev/null <<EOF
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

echo "Created and enabled the pacman-mirror-update service and timer with frequency: $frequency"
