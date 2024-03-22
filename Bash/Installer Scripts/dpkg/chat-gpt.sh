#!/usr/bin/env bash

# Clear the terminal
clear

# Function to log messages
log() {
    echo "[LOG] $1"
}

# Function to log errors
error() {
    echo "[ERROR] $1" >&2
}

# Github repository url for chatgpt releases
REPO_URL="https://github.com/lencx/ChatGPT/releases"

# Function to fetch and install the latest debian release
fetch_and_install_release() {
    log "Fetching the latest release information from $REPO_URL..."

# Use curl to fetch the releases page
    local page_content=$(curl -sSL $REPO_URL)

# Parse the page content to find the debian download link
    local latest_deb_link=$(echo "$page_content" | grep -oP '/lencx/ChatGPT/releases/download/v[0-9.]+/ChatGPT_[0-9.]+_linux_x86_64\.deb' | head -1)

    if [[ -z $latest_deb_link ]]; then
        error "Failed to find the latest Debian release link."
        return 1
    fi

# Construct the complete download link
    local download_link="https://github.com${latest_deb_link}"
    local version=$(echo $latest_deb_link | grep -oP 'ChatGPT_\K[0-9.]+(?=_linux_x86_64\.deb)')

    if [[ -z $version ]]; then
        error "Failed to extract the version number."
        return 1
    fi

    local file_name="ChatGPT_${version}_linux_x86_64.deb"

    echo "Latest Debian release version: $version"
    echo "Download link: $download_link"

    log "Downloading ChatGPT version $version..."
    curl -Lso "$file_name" $download_link

    if [[ ! -f "$file_name" || ! -s "$file_name" ]]; then
        error "Failed to download the file or the file is empty."
        return 1
    fi

    if ! dpkg -I "$file_name" &> /dev/null; then
        error "'$file_name' is not a valid Debian package."
        return 1
    fi

    log "Installing ChatGPT version $version..."
    sudo dpkg -i "$file_name"

    if [[ $? -eq 0 ]]; then
        log "ChatGPT version $version installed successfully."
    else
        error "Failed to install ChatGPT."
        return 1
    fi
}

# Function to uninstall the chatgpt debian package
uninstall_chatgpt() {
    local file_name=$(ls ChatGPT_*.deb 2> /dev/null | head -1)
    if [[ -z $file_name ]]; then
        error "No ChatGPT .deb file found to uninstall."
        return 1
    fi

    local package_name=$(echo "$file_name" | grep -Eo 'ChatGPT.*')
    if [[ -z $package_name ]]; then
        error "Unable to determine the package name from $file_name."
        return 1
    fi

    log "Uninstalling $package_name..."
    sudo dpkg -r $(dpkg -f "$file_name" Package)

    if [[ $? -eq 0 ]]; then
        log "$package_name uninstalled successfully."
    else
        error "Failed to uninstall $package_name."
        return 1
    fi
}

# Main function
main() {
    echo "Choose an option:"
    echo "1. Install latest ChatGPT release"
    echo "2. Uninstall ChatGPT"
    read -p "Enter your choice (1/2): " choice

    case $choice in
        1) fetch_and_install_release ;;
        2) uninstall_chatgpt ;;
        *) error "Invalid choice. Exiting." ;;
    esac
}

# Execute the main function
main
