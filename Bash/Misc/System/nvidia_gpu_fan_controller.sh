#!/usr/bin/env bash

###############################################################################
# NVIDIA Fan Control Setup and Management Script (Root version - improved)
#
# This version is designed to run as root or with sudo. It stores everything
# under /root and sets up a systemd service as root. It also includes safeguards
# and debug messages to help diagnose issues if something stops working after
# configuration changes.
#
# Requirements:
# - Run as root (or with sudo).
# - NVIDIA drivers, nvidia-smi, Python 3, systemd, and optionally nvidia-settings.
#
# Usage:
#   sudo ./a.sh [options]
#
# Options:
#   -h, --help      Show help message
#   -s, --status    Display current GPU temperature and fan speed
#   -l, --log       Display the fan control log
#   -r, --reset     Attempt to reset fan control to automatic mode using nvidia-settings
###############################################################################

set -euo pipefail
IFS=$'\n\t'

# Hardcoded paths for root
BASE_DIR="/root"
VENV_DIR="${BASE_DIR}/fan_control_env"
INSTALL_DIR="${BASE_DIR}/nvidia-fan-settings"
SCRIPT_NAME="nvidia_fan_control.py"
SCRIPT_PATH="${INSTALL_DIR}/${SCRIPT_NAME}"
LOG_FILE="${BASE_DIR}/fan_control.log"
SERVICE_NAME="fan_control.service"
SCRIPT_URL="https://raw.githubusercontent.com/RoversX/nvidia_fan_control_linux/main/nvidia_fan_control.py"

DEFAULT_TEMP_POINTS="[0, 60, 72, 80]"
DEFAULT_FAN_SPEED="[35, 60, 80, 100]"

for cmd in nvidia-smi wget systemctl python3; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found. Please install it first."
        exit 1
    fi
done

show_help() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message and exit"
    echo "  -s, --status        Display current GPU temperature and fan speed"
    echo "  -l, --log           Display the fan control log"
    echo "  -r, --reset         Reset fan control to automatic mode (if supported by nvidia-settings)"
    echo ""
    echo "If no options are provided, the script will set up the environment,"
    echo "prompt for configuration, start the fan control, and create/update the systemd service."
}

show_status() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo "Error: nvidia-smi not found. Please ensure NVIDIA drivers are installed."
        exit 1
    fi
    echo "Current GPU Temperature and Fan Speed:"
    nvidia-smi --query-gpu=temperature.gpu,fan.speed --format=csv,noheader,nounits
}

show_log() {
    if [[ -f "$LOG_FILE" ]]; then
        echo "Fan Control Log:"
        cat "$LOG_FILE"
    else
        echo "Warning: Log file not found."
    fi
}

reset_fan_control() {
    if command -v nvidia-settings &> /dev/null; then
        # Attempt fan reset via nvidia-settings.
        if nvidia-settings -a '[gpu:0]/GpuFanControlState=0' &> /dev/null; then
            echo "Fan control reset to automatic mode using nvidia-settings."
        else
            echo "Warning: Could not set fan control to auto with nvidia-settings. Check if an X environment is available."
        fi
    else
        echo "Warning: nvidia-settings not found. NVML doesn't provide a direct reset method."
        echo "Use nvidia-settings or another tool to revert automatic fan control."
    fi
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--status)
            show_status
            exit 0
            ;;
        -l|--log)
            show_log
            exit 0
            ;;
        -r|--reset)
            reset_fan_control
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
fi

# No arguments: proceed with setup
echo "Do you want to enable automatic or manual fan control settings? (Enter 'automatic' or 'manual')"
read -r control_type

if [[ "$control_type" == "manual" ]]; then
    echo "Do you want to enter custom temperature and fan speed points? (Enter 'yes' or 'no')"
    read -r custom_input

    if [[ "$custom_input" == "yes" ]]; then
        echo "Enter temperature points as a comma-separated list (e.g., 0,60,72,80):"
        read -r temp_points
        echo "Enter fan speed points as a comma-separated list (e.g., 35,60,80,100):"
        read -r fan_speed_points

        TEMP_POINTS="[$temp_points]"
        FAN_SPEED_POINTS="[$fan_speed_points]"
    else
        # User selected manual but not providing custom points, revert to defaults
        echo "No custom points provided. Reverting to default temperature and fan speed points."
        TEMP_POINTS="$DEFAULT_TEMP_POINTS"
        FAN_SPEED_POINTS="$DEFAULT_FAN_SPEED"
    fi
else
    TEMP_POINTS="$DEFAULT_TEMP_POINTS"
    FAN_SPEED_POINTS="$DEFAULT_FAN_SPEED"
fi

mkdir -p "$INSTALL_DIR"
if [[ ! -f "$LOG_FILE" ]]; then
    touch "$LOG_FILE"
fi
chmod 644 "$LOG_FILE"
chown root:root "$LOG_FILE"

# Create and activate Python virtual environment if not already present
if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

python3 -m ensurepip --upgrade &> /dev/null || true
pip install --upgrade pip setuptools wheel &> /dev/null

if ! python3 -c "import pynvml" &> /dev/null; then
    echo "Installing pynvml..."
    pip install pynvml &> /dev/null
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Downloading fan control script..."
    wget --show-progress -cqO "$SCRIPT_PATH" "$SCRIPT_URL"
else
    echo "Fan control script already exists. Updating parameters..."
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Error: Fan control script not found even after download. Check network connectivity or script URL."
    exit 1
fi

echo "Setting temperature points to: $TEMP_POINTS"
echo "Setting fan speed points to: $FAN_SPEED_POINTS"

sed -i "s|temperature_points = .*|temperature_points = $TEMP_POINTS|" "$SCRIPT_PATH"
sed -i "s|fan_speed_points = .*|fan_speed_points = $FAN_SPEED_POINTS|" "$SCRIPT_PATH"
sed -i "s|sleep_seconds = .*|sleep_seconds = 5|" "$SCRIPT_PATH"

deactivate || true

echo "Creating/updating systemd service file..."
cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null
[Unit]
Description=NVIDIA Fan Control Service (root)
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/bin/bash -c 'source $VENV_DIR/bin/activate && python3 $SCRIPT_PATH >> $LOG_FILE 2>&1 && deactivate'
Restart=always
RestartSec=5
User=root
Group=root
Environment='PATH=$VENV_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
Environment='HOME=/root'

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting (or restarting) the fan control service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME" || {
    echo "Error: Failed to start $SERVICE_NAME. Check systemd logs for details:"
    echo "  journalctl -u $SERVICE_NAME -e"
    exit 1
}

echo "Fan control service has been set up and started successfully."
echo "Use '--status' to check GPU temps and fan speeds, '--log' to view logs."
echo "Use '--reset' to attempt resetting fans to auto mode with nvidia-settings."

echo "If the service fails again after changes, check logs with:"
echo "  journalctl -u $SERVICE_NAME -e"
echo "You can rerun this script to reconfigure as needed."
