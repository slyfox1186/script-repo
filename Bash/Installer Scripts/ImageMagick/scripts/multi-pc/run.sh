#!/bin/bash

# Check if at least one argument is provided
if [[ "$#" -eq 0 ]]; then
    echo "Please provide arguments."
    echo "Usage: $0 [-o] -d /path/to/images/directory"
    exit 1
fi

# Initialize variables
OVERWRITE=""
IMAGE_DIR=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    key="$1"
    case "$key" in
        -o)
        OVERWRITE="-o"
        shift
        ;;
        -d)
        IMAGE_DIR="$2"
        shift 2
        ;;
        *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

# Check if IMAGE_DIR is set
if [[ -z "$IMAGE_DIR" ]]; then
    echo "Error: Image directory not specified. Use -d option."
    exit 1
fi

REMOTE_USER="jman"
REMOTE_IP="192.168.50.25"
REMOTE_SSH="$REMOTE_USER@$REMOTE_IP"
OPTIMIZE_SCRIPT="optimize-jpg.py"
DISTRIBUTE_SCRIPT="distribute_files.py"
PYTHON_ENV_LOCAL="$HOME/python-venv/myenv/bin/python"
PYTHON_ENV_REMOTE="/home/jman/python-venv/myenv/bin/python"

# Create random temporary directories
LOCAL_TEMP_DIR=$(mktemp -d /tmp/imoww_local.XXXXXX)
REMOTE_TEMP_DIR=$(ssh $REMOTE_SSH "mktemp -d /tmp/imoww_remote.XXXXXX")

# Function to check if a package is installed on a machine
is_package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

# Function to check if a package is installed on the remote machine
is_remote_package_installed() {
    ssh $REMOTE_SSH "dpkg-query -W -f='\${Status}' $1 2>/dev/null | grep -q 'ok installed'"
}

# Check and install required packages locally
local_packages=("libjpeg62-turbo" "libjpeg62-turbo-dev")
for pkg in "${local_packages[@]}"; do
    if ! is_package_installed "$pkg"; then
        echo "Installing $pkg locally..."
        sudo apt-get update && sudo apt-get install -y "$pkg"
    else
        echo "$pkg is already installed locally."
    fi
done

# Check and install required packages on the remote machine
remote_packages=("libjpeg62" "libjpeg62-dev")
for pkg in "${remote_packages[@]}"; do
    if ! is_remote_package_installed "$pkg"; then
        echo "Installing $pkg on the remote machine..."
        ssh $REMOTE_SSH "sudo apt-get update && sudo apt-get install -y $pkg"
    else
        echo "$pkg is already installed on the remote machine."
    fi
done

# Check if the Python environment exists locally
if [[ ! -f "$PYTHON_ENV_LOCAL" ]]; then
    echo "Python environment not found locally. Creating virtual environment..."
    python3 -m venv ~/python-venv/myenv && source ~/python-venv/myenv/bin/activate && pip install -r requirements.txt || { echo "Error: Failed to create the virtual environment locally."; exit 1; }
fi

# Check if the Python environment exists on the remote machine
if ! ssh $REMOTE_SSH "[ -f $PYTHON_ENV_REMOTE ]"; then
    echo "Python environment not found on the remote machine. Creating virtual environment..."
    ssh $REMOTE_SSH "python3 -m venv ~/python-venv/myenv && source ~/python-venv/myenv/bin/activate && pip install -r /path/to/requirements.txt" || { echo "Error: Failed to create the virtual environment on the remote machine."; exit 1; }
fi

# Ensure the scripts are in the local temporary directory
if [[ ! -f "$LOCAL_TEMP_DIR/$OPTIMIZE_SCRIPT" || ! -f "$LOCAL_TEMP_DIR/$DISTRIBUTE_SCRIPT" ]]; then
    echo "Error: Scripts not found in the temporary directory."
    exit 1
fi

# Copy the scripts to the remote machine
scp "$LOCAL_TEMP_DIR/$OPTIMIZE_SCRIPT" "$REMOTE_SSH:$REMOTE_TEMP_DIR/"
scp "$LOCAL_TEMP_DIR/$DISTRIBUTE_SCRIPT" "$REMOTE_SSH:$REMOTE_TEMP_DIR/"

# Run the distribute_files.py script to distribute the files
$PYTHON_ENV_LOCAL "$LOCAL_TEMP_DIR/$DISTRIBUTE_SCRIPT" "$IMAGE_DIR" "$REMOTE_TEMP_DIR" "$REMOTE_USER" "$REMOTE_IP"

# Define the commands to run in parallel
local_cmd="$PYTHON_ENV_LOCAL $LOCAL_TEMP_DIR/$OPTIMIZE_SCRIPT $OVERWRITE -d \"$IMAGE_DIR\" -t \"\$(nproc --all)\""
remote_cmd="ssh $REMOTE_SSH \"$PYTHON_ENV_REMOTE $REMOTE_TEMP_DIR/$OPTIMIZE_SCRIPT $OVERWRITE -d $REMOTE_TEMP_DIR -t \$(nproc)\""

# Run both commands in parallel
parallel ::: "$local_cmd" "$remote_cmd"

# Sync the processed files back from the remote machine to the local machine
rsync -avz --remove-source-files "$REMOTE_SSH:$REMOTE_TEMP_DIR/" "$IMAGE_DIR/"

# Check if the rsync was successful
if [ $? -eq 0 ]; then
    echo "Files successfully transferred back to local machine."
    
    # Delete any remaining files in the remote directory
    ssh $REMOTE_SSH "find $REMOTE_TEMP_DIR -type f -delete"
    
    echo "Cleaned up remote directory."
else
    echo "Error: Failed to transfer files from remote machine."
fi

# Clean up local temporary directory
rm -rf "$LOCAL_TEMP_DIR"
