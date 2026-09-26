#!/usr/bin/env bash

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
