#!/usr/bin/env bash

# A collection of bash functions to simplify finding, stopping, and starting systemd services.

# --- FIND SERVICE ---
# Searches for a systemd service by keyword(s).
# Usage: find_service <keyword1> [keyword2] ...
find_service() {
    if [[ $# -eq 0 ]]; then
        echo "Error: Please provide at least one search term." >&2
        echo "Usage: find_service <keyword1> [keyword2] ..." >&2
        return 1
    fi
    # Use '|' as an OR operator for grep to find any of the keywords
    local IFS='|'
    sudo systemctl list-units --type=service --all | grep -E --color=always "$*"
}
