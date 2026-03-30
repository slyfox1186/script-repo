#!/usr/bin/env bash

set -euo pipefail

clear

log() {
    echo "[LOG] $1"
}

error() {
    echo "[ERROR] $1" >&2
}

REPO_URL="https://github.com/lencx/ChatGPT/releases/"

fetch_and_install_release() {
    log "Fetching the latest release information from $REPO_URL..."

    local page_content
    page_content=$(curl -sSL "$REPO_URL") || {
        error "Failed to fetch releases page."
        return 1
    }

    local latest_deb_link
    latest_deb_link=$(echo "$page_content" | grep -oP '/lencx/ChatGPT/releases/download/v[0-9.]+/ChatGPT_[0-9.]+_linux_x86_64\.deb' | head -1)

    if [[ -z "$latest_deb_link" ]]; then
        error "Failed to find the latest Debian release link."
        return 1
    fi

    local download_link="https://github.com${latest_deb_link}"
    local version
    version=$(echo "$latest_deb_link" | grep -oP 'ChatGPT_\K[0-9.]+(?=_linux_x86_64\.deb)')

    if [[ -z "$version" ]]; then
        error "Failed to extract the version number."
        return 1
    fi

    local file_name="ChatGPT_${version}_linux_x86_64.deb"

    echo "Latest Debian release version: $version"
    echo "Download link: $download_link"

    log "Downloading ChatGPT version $version..."
    curl -LSo "$file_name" "$download_link" || {
        error "Failed to download the file."
        return 1
    }

    if [[ ! -s "$file_name" ]]; then
        error "Downloaded file is empty."
        return 1
    fi

    if ! dpkg -I "$file_name" &>/dev/null; then
        error "'$file_name' is not a valid Debian package."
        return 1
    fi

    log "Installing ChatGPT version $version..."
    if sudo dpkg -i "$file_name"; then
        log "ChatGPT version $version installed successfully."
    else
        error "Failed to install ChatGPT. Attempting to fix dependencies..."
        sudo apt-get install -f -y || {
            error "Failed to resolve dependencies."
            return 1
        }
    fi
}

uninstall_chatgpt() {
    local pkg_name="chat-gpt"

    if ! dpkg-query -W -f='${Status}' "$pkg_name" 2>/dev/null | grep -q 'install ok installed'; then
        error "ChatGPT does not appear to be installed."
        return 1
    fi

    log "Uninstalling $pkg_name..."
    if sudo dpkg -r "$pkg_name"; then
        log "$pkg_name uninstalled successfully."
    else
        error "Failed to uninstall $pkg_name."
        return 1
    fi
}

main() {
    echo "Choose an option:"
    echo "1. Install latest ChatGPT release"
    echo "2. Uninstall ChatGPT"
    read -rp "Enter your choice (1/2): " choice

    case "$choice" in
        1) fetch_and_install_release ;;
        2) uninstall_chatgpt ;;
        *) error "Invalid choice. Exiting." ;;
    esac
}

main
