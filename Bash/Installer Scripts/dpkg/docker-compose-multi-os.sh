#!/usr/bin/env bash

clear

# Function to log messages
log() {
    echo "[LOG] $1"
}

# Function to log errors
error() {
    echo "[ERROR] $1" >&2
}

# GitHub repository URL for Docker Compose releases
REPO_URL="https://github.com/docker/compose/releases"

# Function to determine the correct Docker Compose binary for the system
get_compose_filename() {
    local os_type
    local arch_type

    # Detect OS type
    os_type=$(uname -s | tr '[:upper:]' '[:lower:]')
    # Detect architecture
    arch_type=$(uname -m)

    case "$os_type" in
        "linux")
            case "$arch_type" in
                "x86_64") arch_type="x86_64" ;;
                "armv6l"|"armv6") arch_type="armv6" ;;
                "armv7l"|"armv7") arch_type="armv7" ;;
                "aarch64") arch_type="aarch64" ;;
                *) echo "Unsupported Linux architecture: $arch_type"; exit 1 ;;
            esac
            ;;
        "darwin")
            case "$arch_type" in
                "x86_64") arch_type="x86_64" ;;
                "arm64") arch_type="aarch64" ;;
                *) echo "Unsupported Darwin architecture: $arch_type"; exit 1 ;;
            esac
            ;;
        *)
            echo "Unsupported operating system: $os_type"
            exit 1
            ;;
    esac

    echo "docker-compose-${os_type}-${arch_type}"
}

# Function to fetch and install the latest Docker Compose release
fetch_and_install_docker_compose() {
    log "Fetching the latest release information from $REPO_URL..."

    local page_content=$(curl -sSL $REPO_URL)
    local compose_filename=$(get_compose_filename)

    # Match the pattern and construct the download link
    local base_link=$(echo "$page_content" | grep -oP "/docker/compose/releases/download/v[0-9.]+/${compose_filename}" | head -1)
    local download_link="https://github.com${base_link}"

    if [[ -z $base_link ]]; then
        error "Failed to find the Docker Compose release link for $compose_filename."
        return 1
    fi

    local file_name="/usr/local/bin/docker-compose"

    log "Latest release found for $compose_filename. Download link: $download_link"

    log "Downloading Docker Compose..."
    sudo curl -L "$download_link" -o "$file_name"

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
