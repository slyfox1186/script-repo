#!/usr/bin/env bash

# Export the public SSH key stored inside a private SSH key
keytopub() {
    local opub okey
    clear; ls -1AhFv --color --group-directories-first

    echo "Enter the full paths for each file"
    echo
    read -r -p "Private key: " okey
    read -r -p "Public key: " opub
    echo
    if [[ -f "$okey" ]]; then
        chmod 600 "$okey"
    else
        echo "Warning: FILE missing = $okey"
        read -r -p "Press Enter to return."
        return 1
    fi
    ssh-keygen -b "4096" -y -f "$okey" > "$opub"
    chmod 644 "$opub"
    cp -f "$opub" "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
}
