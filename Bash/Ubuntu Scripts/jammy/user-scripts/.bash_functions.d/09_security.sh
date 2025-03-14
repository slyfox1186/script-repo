#!/bin/bash
# Crypto and Security Functions

## SSH-KEYGEN ##

# Create a new private and public SSH key pair
new_key() {
    local bits comment name pass type
    clear

    echo "Encryption type: [[ rsa | dsa | ecdsa ]]"
    echo
    read -p "Your choice: " type
    clear

    echo "[i] Choose the key bit size"
    echo "[i] Values encased in \"()\" are recommended"
    echo

    if [[ "$type" == "rsa" ]]; then
        echo "[i] rsa: [[ 512 | 1024 | (2048) | 4096 ]]"
        echo
    elif [[ "$type" == "dsa" ]]; then
        echo "[i] dsa: [[ (1024) | 2048 ]]"
        echo
    elif [[ "$type" == "ecdsa" ]]; then
        echo "[i] ecdsa: [[ (256) | 384 | 521 ]]"
        echo
    fi

    read -p "Your choice: " bits
    clear

    echo "[i] Choose a password"
    echo "[i] For no password just press enter"
    echo
    read -p "Your choice: " pass
    clear

    echo "[i] For no comment just press enter"
    read -p "Your choice: " comment
    clear

    echo "[i] Enter the ssh key name"
    read -p "Your choice: " name
    clear

    echo "[i] Your choices"
    echo "[i] Type: $type"
    echo "[i] bits: $bits"
    echo "[i] Password: $pass"
    echo "[i] comment: $comment"
    echo "[i] Key name: $name"
    echo
    read -p "Press enter to continue or ^c to exit"
    clear

    ssh-keygen -q -b "$bits" -t "$type" -N "$pass" -C "$comment" -f "$name"

    chmod 600 "$PWD/$name"
    chmod 644 "$PWD/$name.pub"
    clear

    echo "File: $PWD/$name"
    cat "$PWD/$name"

    echo
    echo "File: $PWD/$name.pub"
    cat "$PWD/$name.pub"
    echo
}

# Export the public SSH key stored inside a private SSH key
keytopub() {
    local opub okey
    clear; ls -1AhFv --color --group-directories-first

    echo "Enter the full paths for each file"
    echo
    read -p "Private key: " okey
    read -p "Public key: " opub
    echo
    if [[ -f "$okey" ]]; then
        chmod 600 "$okey"
    else
        echo "Warning: FILE missing = $okey"
        read -p "Press Enter to exit."
        exit 1
    fi
    ssh-keygen -b "4096" -y -f "$okey" > "$opub"
    chmod 644 "$opub"
    cp -f "$opub" "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    unset "$okey" "$opub"
}

# Clear Bash History
clearh() {
    history -c
    clear; ls -1AhFv
    echo -e "\n${GREEN}Bash History Cleared${NC}"
}