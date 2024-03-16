#!/usr/bin/env bash
# shellcheck disable=SC2068,SC2162

# Define variables and arrays
url="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Debian%20Scripts/bookworm/user-scripts/bookworm-scripts.txt"
script_array=(".bashrc" ".bash_aliases" ".bash_functions")
tf=$(mktemp)
td=$(mktemp -d)

# Create functions
fail() {
    echo -e "\\n[ERROR] $1\\n"
    read -p "Press enter to exit."
    exit 1
}

# Download the required apt packages
sudo apt-get -y install wget

# Change into the temporary directory
cd "$td" || exit 1

# Use 'cat' with a here-document to write multiline text to the temporary file
cat > "$tf" <<'EOF'
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Debian%20Scripts/bookworm/user-scripts/.bashrc
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Debian%20Scripts/bookworm/user-scripts/.bash_aliases
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Debian%20Scripts/bookworm/user-scripts/.bash_functions
EOF

# Download the user scripts from GitHub
wget -qN - -i "$tf"

# Delete all files except those that start with a "." or end with ".sh"
find . ! \( -name ".*" -o -name "*.sh" \) -type f -delete 2>/dev/null

# Move and update ownership of user scripts to the user's home folder
for script in "${script_array[@]}"; do
    cp -f "$script" "$HOME" || fail "Failed to move $script to $HOME. Line $LINENO"
    chown "$USER":"$USER" "$HOME/$script" || fail "Failed to update permissions for $script. Line $LINENO"
done

# Open each script with the nano editor
cd "$HOME" || exit 1
for script in "${script_array[@]}"; do
    command -v nano &>/dev/null || fail "The script failed to open the newly installed scripts using the EDITOR \"nano\"."
    nano "$script"
done

# Cleanup the temp files
sudo rm -fr "$td"
