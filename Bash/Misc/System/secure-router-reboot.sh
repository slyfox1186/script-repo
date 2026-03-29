#!/usr/bin/env bash

# Define file and directory names
key_file="encryption_key.key"
encrypted_config_file="encrypted_config.txt"
encryption_script="encrypt_config.py"
decryption_script="decrypt_config.py"
reboot_script="reboot_router.py"
log_file="setup_log.txt"
ip_regex='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
port_regex='^[0-9]+$'
user_regex='^[a-zA-Z0-9_-]+$'

# Create necessary directory and start logging
mkdir -p "$HOME/router_config"
cd "$HOME/router_config"
touch "$log_file"
echo "$(date) - Started setup script" >> "$log_file"

# Function to validate IP address
validate_ip() {
    if [[ "$1" =~ $ip_regex ]]; then
        echo "Valid IP address."
    else
        echo "Invalid IP address. Exiting..."
        echo "$(date) - Invalid IP address provided: $1" >> "$log_file"
        exit 1
    fi
}

# Function to generate SSH key with passphrase
generate_ssh_key() {
    local ssh_key_path="$1"
    echo "An SSH key generation request has been made."
    echo "Do you want to create a new SSH key at $ssh_key_path? Existing keys will be overwritten."
    read -p "Create new key? (y/n): " create_key_choice
    if [[ "$create_key_choice" == "y" ]]; then
        read -sp "Enter a passphrase for the SSH key (leave blank for no passphrase): " ssh_passphrase
        echo
        ssh-keygen -t rsa -b 4096 -f "$ssh_key_path" -N "$ssh_passphrase"
        chmod 600 "$ssh_key_path"
        echo "SSH key generated and saved to $ssh_key_path."
        echo "$(date) - New SSH key generated at $ssh_key_path" >> "$log_file"

        # Add SSH key to ssh-agent for convenience
        eval "$(ssh-agent -s)"
        ssh-add "$ssh_key_path"

        echo "Remember to update the public key on all devices that require this key for access."
        echo "You can find the public key at $ssh_key_path.pub"
    else
        echo "No new SSH key will be generated."
        echo "Using existing SSH key at $ssh_key_path."
        echo "$(date) - Using existing SSH key at $ssh_key_path" >> "$log_file"
        ssh-add "$ssh_key_path"
    fi
}

# Function to create Python encryption script
generate_encryption_script() {
    cat <<EOF >"$encryption_script"
from cryptography.fernet import Fernet
import json

def encrypt_data():
    key = Fernet.generate_key()
    with open('$key_file', 'wb') as key_file:
        key_file.write(key)
    cipher = Fernet(key)
    config_data = json.dumps({
        'ip': '$ip',
        'username': '$username',
        'ssh_key_path': '$ssh_key_path',
        'port': '$port'
    })
    encrypted_data = cipher.encrypt(config_data.encode('utf-8'))
    with open('$encrypted_config_file', 'wb') as encrypted_file:
        encrypted_file.write(encrypted_data)

if __name__ == "__main__":
    encrypt_data()
EOF
    chmod 700 "$encryption_script"
    python3 "$encryption_script"
    echo "Encryption script executed and configuration data encrypted."
    echo "$(date) - Encryption script executed" >> "$log_file"
}

# Function to create Python decryption script
generate_decryption_script() {
    cat <<EOF >"$decryption_script"
from cryptography.fernet import Fernet
import json

def decrypt_data():
    with open('$key_file', 'rb') as key_file:
        key = key_file.read()
    cipher = Fernet(key)
    with open('$encrypted_config_file', 'rb') as encrypted_file:
        encrypted_data = encrypted_file.read()
    decrypted_data = cipher.decrypt(encrypted_data)
    config = json.loads(decrypted_data.decode('utf-8'))
    return config

if __name__ == "__main__":
    config = decrypt_data()
    print(config)
EOF
    chmod 700 "$decryption_script"
    echo "Decryption script created."
    echo "$(date) - Decryption script created" >> "$log_file"
}

# Function to create Python reboot script
generate_reboot_script() {
    cat <<EOF >"$reboot_script"
import subprocess
from decrypt_config import decrypt_data

def reboot_router():
    config = decrypt_data()
    subprocess.run(['ssh', '-i', config['ssh_key_path'], '-o', 'StrictHostKeyChecking=ask', '-p', str(config['port']), f"{config['username']}@{config['ip']}", 'reboot'])

if __name__ == "__main__":
    reboot_router()
EOF
    chmod 700 "$reboot_script"
    echo "Reboot script created."
    echo "$(date) - Reboot script created" >> "$log_file"
}

# Collect details from the user
read -p "Enter the IP address of the router: " ip
validate_ip "$ip"

read -p "Enter the SSH username: " username
if [[ ! "$username" =~ $user_regex ]]; then
    echo "Invalid SSH username. Only alphanumeric characters, underscores, and hyphens are allowed. Exiting..."
    echo "$(date) - Invalid SSH username provided: $username" >> "$log_file"
    exit 1
fi

read -p "Enter the SSH port: " port
if [[ ! "$port" =~ $port_regex ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "Invalid SSH port. It must be a number between 1 and 65535. Exiting..."
    echo "$(date) - Invalid SSH port provided: $port" >> "$log_file"
    exit 1
fi

read -p "Enter the path to the SSH key (default: $HOME/.ssh/id_rsa): " ssh_key_path
ssh_key_path="${ssh_key_path:-$HOME/.ssh/id_rsa}"

# Ask user if they want to generate a new SSH key
read -p "Would you like to generate a new SSH key or use the existing one? (new/use): " key_choice
if [[ "$key_choice" == "new" ]]; then
    generate_ssh_key "$ssh_key_path"
else
    echo "Using existing SSH key at $ssh_key_path."
fi

generate_encryption_script
generate_decryption_script
generate_reboot_script

echo "Setup complete. All scripts are prepared and available in $HOME/router_config."
echo "$(date) - Setup completed successfully" >> "$log_file"

chmod 600 "$key_file"
chmod 600 "$encrypted_config_file"
chmod 600 "$log_file"

# Ask user if they want to run the reboot script now
read -p "Do you want to run the reboot script now? (y/n): " run_reboot
if [[ "$run_reboot" == "y" ]]; then
    python3 "$reboot_script"
    echo "Reboot script executed."
    echo "$(date) - Reboot script executed" >> "$log_file"
else
    echo "Reboot script not executed. You can run it later using: python3 $HOME/router_config/$reboot_script"
fi
