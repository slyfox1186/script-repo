#!/usr/bin/env bash

# Define variables
VENV_DIR="$HOME/fan_control_env"
SCRIPT_URL="https://raw.githubusercontent.com/RoversX/nvidia_fan_control_linux/main/nvidia_fan_control.py"
SCRIPT_NAME="nvidia_fan_control.py"
LOG_FILE="$HOME/fan_control.log"

# Function to display help message
show_help() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message and exit"
    echo "  -s, --status        Display current GPU temperature and fan speed"
    echo "  -l, --log           Display the fan control log"
    echo "  -r, --reset         Reset fan control to automatic mode"
    echo ""
    echo "If no options are provided, the script will set up the environment and start the fan control."
}

# Function to display current GPU status
show_status() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo "Error: nvidia-smi not found. Please ensure NVIDIA drivers are installed."
        exit 1
    fi
    nvidia-smi --query-gpu=temperature.gpu,fan.speed --format=csv,noheader,nounits
}

# Function to display the log file
show_log() {
    if [[ -f "$LOG_FILE" ]]; then
        cat "$LOG_FILE"
    else
        echo "Log file not found."
    fi
}

# Function to reset fan control to automatic mode
reset_fan_control() {
    if [[ -f "$VENV_DIR/bin/activate" ]]; then
        source "$VENV_DIR/bin/activate"
        python3 -c "
import pynvml
pynvml.nvmlInit()
device_count = pynvml.nvmlDeviceGetCount()
for i in range(device_count):
    handle = pynvml.nvmlDeviceGetHandleByIndex(i)
    fan_count = pynvml.nvmlDeviceGetFanCount(handle)
    for j in range(fan_count):
        pynvml.nvmlDeviceSetDefaultFanSpeed_v2(handle, j)
pynvml.nvmlShutdown()
"
        deactivate
        echo "Fan control reset to automatic mode."
    else
        echo "Virtual environment not found. Cannot reset fan control."
    fi
}

# Parse command-line arguments
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
        ;;
esac

# Create and activate Python virtual environment
if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# Install pynvml if not already installed
if ! python3 -c "import pynvml" &> /dev/null; then
    pip install pynvml
fi

# Download the fan control script
if [[ ! -f "$SCRIPT_NAME" ]]; then
    wget --show-progress -cqO "$SCRIPT_NAME" "$SCRIPT_URL"
fi

# Modify fan control script parameters
sed -i 's/temperature_points = .*/temperature_points = [0, 60, 72, 80]/' "$SCRIPT_NAME"
sed -i 's/fan_speed_points = .*/fan_speed_points = [35, 60, 80, 100]/' "$SCRIPT_NAME"
sed -i 's/sleep_seconds = .*/sleep_seconds = 5/' "$SCRIPT_NAME"

# Run the fan control script
sudo -E bash -c "
    source \"$VENV_DIR/bin/activate\"
    python3 \"$SCRIPT_NAME\" &> \"$LOG_FILE\"
    deactivate
"
