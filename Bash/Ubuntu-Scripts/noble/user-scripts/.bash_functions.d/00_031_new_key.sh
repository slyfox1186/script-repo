#!/usr/bin/env bash

## SSH-KEYGEN ##

# Create a new private and public SSH key pair
new_key() {
    local bits comment name pass type
    clear

    echo "Encryption type: [[ rsa | dsa | ecdsa ]]"
    echo
    read -r -p "Your choice: " type
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

    read -r -p "Your choice: " bits
    clear

    echo "[i] Choose a password"
    echo "[i] For no password just press enter"
    echo
    read -r -p "Your choice: " pass
    clear

    echo "[i] For no comment just press enter"
    read -r -p "Your choice: " comment
    clear

    echo "[i] Enter the ssh key name"
    read -r -p "Your choice: " name
    clear

    echo "[i] Your choices"
    echo "[i] Type: $type"
    echo "[i] bits: $bits"
    echo "[i] Password: $pass"
    echo "[i] comment: $comment"
    echo "[i] Key name: $name"
    echo
    read -r -p "Press enter to continue or ^c to exit"
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
