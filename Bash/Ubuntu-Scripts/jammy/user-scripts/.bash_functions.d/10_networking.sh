#!/bin/bash
# Networking Functions

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

# WGET command
mywget() {
    local outfile url
    if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        read -p "Please enter the output file name: " outfile
        read -p "Please enter the URL: " url
        echo
        wget --out-file="$outfile" "$url"
    else
        wget --out-file="$1" "$2"
    fi
}

adl() {
    if [[ $# -ne 2 ]]; then
        echo "Usage: adl <output_name> <url>"
        return 1
    fi

    local output_name="$1"
    local url="$2"

    # Run aria2c with the provided arguments
    aria2c --continue -x16 -j16 --out="$output_name" "$url"

    # Check if the download was successful
    if [[ $? -eq 0 ]]; then
        echo "Download completed successfully: $output_name"
    else
        echo "Error: Download failed for $url"
        return 2
    fi
}

padl() {
    # Get the clipboard contents using PowerShell
    clipboard=$(pwsh.exe -Command "Get-Clipboard")

    # Split the clipboard contents into an array using whitespace as the delimiter
    IFS=' ' read -r -a args <<< "$clipboard"

    # Check if the number of arguments is less than 2
    if [ ${#args[@]} -lt 2 ]; then
        echo "Error: Two arguments are required: output file and download URL"
        return 1
    fi

    # Extract the first argument as the output file
    output_file="${args[0]}"

    # Extract the remaining arguments as the download URL and remove trailing whitespace
    url=$(echo "${args[@]:1}" | tr -d '[:space:]')

    # Call the 'adl' function with the output file and URL as separate arguments
    adl "$output_file" "$url"
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
    read -p "Filename: " filename
    read -p "Extension: " extension
    read -p "Path: " path
    read -p "URL: " url

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

####################
## RSYNC COMMANDS ##
####################

rsr() {
    local destination source modified_source

    # you must add an extra folder that is a period "/./" between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the source folder instead of the source
    # folder and its subfiles only.

    echo "This rsync command will recursively copy the source folder to the chosen destination."
    echo "The original files will still be located in the source folder."
    echo "If you want to move the files (which deletes the originals then use the function 'rsrd'."
    echo "Please enter the full paths of the source and destination directories."
    echo

    read -p "Enter the source path: " source
    read -p "Enter the destination path: " destination
    modified_source=$(echo "$source" | sed 's:/[^/]*$::')"'/./'"$(echo "$source" | sed 's:.*/::')
    echo

    rsync -aqvR --acls --perms --mkpath --info=progress2 "$modified_source" "$destination"
}

rsrd() {
    local destination source modified_source

    # you must add an extra folder that is a period "/./" between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the souce folder instead of the source
    # folder and its subfiles only.

    echo "This rsync command will recursively copy the source folder to the chosen destination."
    echo "The original files will be DELETED after they have been copied to the destination."
    echo "If you want to move the files (which deletes the originals then use the function 'rsrd'."
    echo "Please enter the full paths of the source and destination directories."
    echo

    read -p "Enter the source path: " source
    read -p "Enter the destination path: " destination
    modified_source=$(echo "$source" | sed 's:/[^/]*$::')"'/./'"$(echo "$source" | sed 's:.*/::')
    echo

    rsync -aqvR --acls --perms --mkpath --remove-source-files "$modified_source" "$destination"
}

# The master script download menu for github repository script-repo
dlmaster() {
    local script_path="/usr/local/bin/download-master.py"
    local script_url="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Python3/download-master.py"

    # Check if the script exists
    if [[ ! -f "$script_path" ]]; then
        echo "The required script does not exist. Downloading now."
        # Download the script
        sudo wget --show-progress -cqO "$script_path" "$script_url"    
        # Set the owner to root and permissions to 755
        sudo chown root:root "$script_path"
        sudo chmod 755 "$script_path"
        echo "The required script was successfully installed."
        sleep 3
        clear
    fi

    # Run the script
    python3 "$script_path"
}