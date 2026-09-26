#!/usr/bin/env bash

town() {
    local files
    files=("$@")

    for file in "${files[@]}"; do
        if [[ -e "$file" ]]; then
            if sudo chmod 755 "$file" && sudo chown "$USER":"$USER" "$file"; then
                clear
                ls -1AvhF --color --group-directories-first
            else
                clear
                echo "Failed to change ownership and permissions of: $file"
                return 1
            fi
        else
            clear
            echo "File does not exist: $file"
            return 1
        fi
    done
}
