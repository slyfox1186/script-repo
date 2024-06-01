#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]]; then
    echo "You must execute the script as root or with sudo."
    exit 1
fi

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

# Function to determine the correct docker compose binary for the system
get_compose_filename() {
# Detect os type and convert to lowercase
    os_type=$(uname -s | tr '[:upper:]' '[:lower:]')
# Detect architecture and remove any unwanted characters
    arch_type=$(uname -m | tr -d '\n\r')

    case "$os_type" in
        linux)
            case "$arch_type" in
                x86_64) arch_type="x86_64" ;;
                armv6l|armv6) arch_type="armv6" ;;
                armv7l|armv7) arch_type="armv7" ;;
                aarch64) arch_type="aarch64" ;;
                *) echo "Unsupported Linux architecture: $arch_type"; exit 1 ;;
            esac
            ;;
        darwin)
            case "$arch_type" in
                x86_64) arch_type="x86_64" ;;
                arm64) arch_type="aarch64" ;;
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

# Function to fetch and install the latest docker compose release
fetch_and_install_docker_compose() {
    log "Fetching the latest release information from $REPO_URL..."

    local file_name=$(get_compose_filename)

# Match the pattern and construct the download link
    local base_link=$(curl -sSL "$REPO_URL" | grep -oP "/docker/compose/releases/download/v[0-9.]+/" | head -1)
    local download_link="https://github.com${base_link}${file_name}"
    
    if [[ -z $base_link ]]; then
        error "Failed to find the Docker Compose release link for $file_name"
        return 1
    fi

        case "$file_name" in
            docker-compose-linux-x86_64) output_file_name="${file_name/$file_name/docker-compose}" ;;
            docker-compose-linux-armv6) output_file_name="${file_name/$file_name/docker-compose}" ;;
            docker-compose-linux-armv7) output_file_name="${file_name/$file_name/docker-compose}" ;;
            docker-compose-linux-aarch64) output_file_name="${file_name/$file_name/docker-compose}" ;;
            docker-compose-darwin-x86_64) output_file_name="${file_name/$file_name/docker-compose}" ;;
            docker-compose-darwin-aarch64) output_file_name="${file_name/$file_name/docker-compose}" ;;
            *) echo "Could not trim the Arch type: $arch_type"; exit 1 ;;
        esac

    save_to_path="/usr/local/bin/$output_file_name"

    echo
    log "Successfully identified the latest release"
    log "File Name: $file_name"
    log "Download link: $download_link"
    echo
    log "Downloading Docker Compose..."

    curl -Lso "$save_to_path" "$download_link"

    if [[ ! -f "$save_to_path" || ! -s "$save_to_path" ]]; then
        error "Failed to download Docker Compose or the file is empty."
        return 1
    else
        echo
        log "Successfully saved the file as: $save_to_path"
    fi

    chmod +x "$save_to_path"

    log "Docker Compose installed successfully."
}

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "curl could not be found. Please install curl and run this script again."
    exit 1
fi

# Execute the function
fetch_and_install_docker_compose
