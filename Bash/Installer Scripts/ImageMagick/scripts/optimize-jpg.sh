function imow() {
    # Capture the current working directory
    local cwd="$PWD"

    # Check if the script exists in /usr/local/bin
    if [[ ! -f /usr/local/bin/imow ]]; then
        echo "imow script not found. Downloading..."
        local dir=$(mktemp -d)
        cd "$dir" || { echo "Failed to cd into temp directory: $dir"; return 1; }

        # Download the script
        curl -Lso imow "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-jpg.sh"
        
        # Move and setup the script only if the download was successful
        if [[ -f imow ]]; then
            echo "Setting up imow script..."
            sudo mv imow /usr/local/bin/
            sudo chown root:root /usr/local/bin/imow
            sudo chmod 755 /usr/local/bin/imow
            cd "$cwd" # Return to the original directory
            sudo rm -rf "$dir" # Cleanup
        else
            echo "Download failed. Exiting."
            cd "$cwd" # Return to the original directory if download fails
            return 1
        fi
    fi

    clear
    echo "Executing imow with the current directory: $cwd"
    
    # Execute the script with the current working directory
    if ! /usr/local/bin/imow --dir "$cwd" --overwrite; then
        echo "Failed to execute: /usr/local/bin/imow --dir $cwd --overwrite"
        return 1
    fi
}
