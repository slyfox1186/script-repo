#!/usr/bin/env bash

# Script to download and install bash configuration files
# GitHub: https://github.com/slyfox1186/script-repo

# Source common utilities (adjust path as needed since this is in a subdirectory)
source "$(dirname "$(dirname "$0")")/common-utils.sh"

# Define the scripts to download and install
script_array=(".bashrc" ".bash_aliases" ".bash_functions")
tf=$(mktemp)
td=$(mktemp -d)

# Check for wget and install if missing
if ! command -v wget &>/dev/null; then
    echo "Installing wget..."
    install_pkg "wget"
    clear
fi

# Change to temporary directory
cd "$td" || fail "Failed to change to temporary directory"

# Create list of URLs to download
cat > "$tf" <<'EOF'
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc
EOF

# Download files
echo "Downloading bash configuration files..."
wget -qN - -i "$tf"

# Clean up unnecessary files
find . ! \( -name ".*" -o -name "*.sh" \) -type f -delete 2>/dev/null

# Copy files to home directory
echo "Installing bash configuration files..."
for script in "${script_array[@]}"; do
    cp -f "$script" "$HOME" || fail "Failed to move $script to $HOME. Line $LINENO"
    chown "$USER":"$USER" "$HOME/$script" || fail "Failed to update permissions for $script. Line $LINENO"
    echo "Installed $script"
done

# Open files for editing
echo "Opening files for editing..."
cd "$HOME" || fail "Failed to change to home directory"

# Check for and use editors systematically
for script in "${script_array[@]}"; do
    if command -v nano &>/dev/null; then
        nano "$script"
    else
        # Try other editors in a fallback sequence
        open_editor "$script"
    fi
done

# Clean up
echo "Cleaning up temporary files..."
rm -fr "$tf" "$td"
echo "Installation complete!"
