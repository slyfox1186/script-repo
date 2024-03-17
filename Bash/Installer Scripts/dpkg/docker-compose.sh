#!/Usr/bin/env bash

clear

# Function to log messages
log() {
    echo "[LOG] $1"
}

# Function to log errors
error() {
    echo "[ERROR] $1" >&2
}

# Github repository url for docker compose releases
REPO_URL="https://github.com/docker/compose/releases"

# Function to fetch and install the latest docker compose release
fetch_and_install_docker_compose() {
    log "Fetching the latest release information from $REPO_URL..."

    local page_content=$(curl -sSL $REPO_URL)

# Match the pattern and append '-linux-x86_64' to the url
    local base_link=$(echo "$page_content" | grep -oP '/docker/compose/releases/download/v[0-9.]+/docker-compose' | head -1)
    local download_link="https://github.com$base_link-linux-x86_64"

    if [[ -z $base_link ]]; then
        error "Failed to find the latest Docker Compose release link."
        return 1
    fi

    local file_name="/usr/local/bin/docker-compose"

    log "Latest release found. Download link: $download_link"

    log "Downloading Docker Compose..."
    sudo curl -Lso "$file_name" "$download_link"

    if [[ ! -f "$file_name" || ! -s "$file_name" ]]; then
        error "Failed to download Docker Compose or the file is empty."
        return 1
    fi

    sudo chmod +x "$file_name"

    log "Docker Compose installed successfully."
}

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "curl could not be found. Please install curl and run this script again."
    exit 1
fi

# Execute the function
fetch_and_install_docker_compose
