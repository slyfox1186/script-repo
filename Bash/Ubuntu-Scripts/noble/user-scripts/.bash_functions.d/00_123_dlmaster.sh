#!/usr/bin/env bash

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
