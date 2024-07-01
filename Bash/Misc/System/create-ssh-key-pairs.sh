#!/usr/bin/env bash

# Variables
ssh_dir="$HOME/.ssh"
private_key="$ssh_dir/id_rsa"
public_key="$ssh_dir/id_rsa.pub"
authorized_keys="$ssh_dir/authorized_keys"

log() {
    local msg
    msg="$1"
    echo "[LOG] $msg"
}

error_exit() {
    local msg
    msg="$1"
    echo "[ERROR] $msg" >&2
    exit 1
}

# Prompt for key size and email address
read -p "Enter the key size for SSH key generation (e.g., 1024, 2048, 4096): " key_size
read -p "Enter the email address to associate with the SSH key: " email_address

# Check if ~/.ssh directory exists
if [[ ! -d "$ssh_dir" ]]; then
    read -p "~/.ssh directory does not exist. Do you want to create it? (y/n) " create_ssh_dir
    if [[ "$create_ssh_dir" == "y" ]]; then
        mkdir -p "$ssh_dir" || error_exit "Failed to create ~/.ssh directory"
        chmod 700 "$ssh_dir" || error_exit "Failed to set permissions on ~/.ssh directory"
        log "Created ~/.ssh directory and set permissions to 700"
    else
        error_exit "User chose not to create ~/.ssh directory. Exiting."
    fi
fi

# Check if id_rsa and id_rsa.pub files exist
if [[ ! -f "$private_key" || ! -f "$public_key" ]]; then
    read -p "SSH key pair does not exist. Do you want to create it? (y/n) " create_keys
    if [[ "$create_keys" == "y" ]]; then
        ssh-keygen -t rsa -b "$key_size" -f "$private_key" -N "" -C "$email_address" || error_exit "Failed to generate SSH key pair"
        log "Generated SSH key pair"
    else
        error_exit "User chose not to create SSH key pair. Exiting."
    fi
fi

# Check if authorized_keys file exists
if [[ ! -f "$authorized_keys" ]]; then
    read -p "authorized_keys file does not exist. Do you want to create it? (y/n) " create_auth_keys
    if [[ "$create_auth_keys" == "y" ]]; then
        touch "$authorized_keys" || error_exit "Failed to create authorized_keys file"
        chmod 600 "$authorized_keys" || error_exit "Failed to set permissions on authorized_keys file"
        log "Created authorized_keys file and set permissions to 600"
    else
        error_exit "User chose not to create authorized_keys file. Exiting."
    fi
fi

# Copy public key contents into authorized_keys file
if grep -q "$(cat "$public_key")" "$authorized_keys"; then
    log "Public key already exists in authorized_keys file"
else
    cat "$public_key" >> "$authorized_keys" || error_exit "Failed to copy public key contents to authorized_keys file"
    log "Copied public key contents to authorized_keys file"
fi

log "Script completed successfully"
