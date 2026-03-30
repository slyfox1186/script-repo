#!/usr/bin/env bash

set -euo pipefail

ext="sh"

prompt_user() {
    while true; do
        echo "Include the parent folder?"
        echo
        echo "[1] Yes"
        echo "[2] No"
        echo
        read -rp "Your choices are (1 or 2): " choice
        clear

        case "$choice" in
            1|2) return ;;
            *)   echo "Invalid choice, try again." ;;
        esac
    done
}

prompt_user

mapfile -t store_paths < <(
    if [[ "$choice" == "1" ]]; then
        find . -type f -iname "*.$ext" -print
    else
        find . -mindepth 2 -type f -iname "*.$ext" -print
    fi
)

for path in "${store_paths[@]}"; do
    echo "$PWD/$path"
done
