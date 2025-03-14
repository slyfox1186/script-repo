#!/usr/bin/env bash

# Script to download and install bash configuration files
# GitHub: https://github.com/slyfox1186/script-repo

# Source common utilities (adjust path as needed since this is in a subdirectory)
source "$(dirname "$(dirname "$0")")/common-utils.sh"

# Define the scripts to download and install
script_array=(".bashrc" ".bash_aliases" ".bash_functions")
# Define the subdirectories
subdir_array=(".bashrc.d" ".bash_aliases.d" ".bash_functions.d")
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

# Create list of URLs to download main files
cat > "$tf" <<'EOF'
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc
EOF

# Download main files
echo "Downloading main bash configuration files..."
wget -qN - -i "$tf"

# Download subdirectory files
echo "Creating and downloading subdirectory files..."
# Create the subdirectories in the temporary directory
for subdir in "${subdir_array[@]}"; do
    mkdir -p "$subdir"
done

# Download .bash_aliases.d files
mkdir -p ".bash_aliases.d"
wget -qN -P ".bash_aliases.d" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases.d/01_sudo_aliases.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases.d/02_system_control.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases.d/03_network.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases.d/04_docker.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases.d/05_filesystem.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases.d/06_package_management.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases.d/07_editors.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_aliases.d/08_project_specific.sh"

# Download .bash_functions.d files
mkdir -p ".bash_functions.d"
wget -qN -P ".bash_functions.d" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/01_gui_apps.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/02_filesystem.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/03_text_processing.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/04_compression.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/06_process_management.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/07_dev_tools.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/08_file_analysis.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/09_security.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/10_networking.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/11_multimedia.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/12_utilities.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/13_database.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bash_functions.d/14_docker.sh"

# Download .bashrc.d files
mkdir -p ".bashrc.d"
wget -qN -P ".bashrc.d" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc.d/01_history.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc.d/02_shell_options.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc.d/03_prompt.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc.d/04_dircolors.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc.d/05_environment.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc.d/06_path.sh" \
    "https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Ubuntu%20Scripts/jammy/user-scripts/.bashrc.d/07_external_tools.sh"

# Clean up unnecessary files
find . ! \( -name ".*" -o -name "*.sh" \) -type f -delete 2>/dev/null

# Create subdirectories in home directory if they don't exist
echo "Creating subdirectories in home directory..."
for subdir in "${subdir_array[@]}"; do
    mkdir -p "$HOME/$subdir" || fail "Failed to create $HOME/$subdir. Line $LINENO"
done

# Copy main files to home directory
echo "Installing main bash configuration files..."
for script in "${script_array[@]}"; do
    cp -f "$script" "$HOME" || fail "Failed to move $script to $HOME. Line $LINENO"
    chown "$USER":"$USER" "$HOME/$script" || fail "Failed to update permissions for $script. Line $LINENO"
    echo "Installed $script"
done

# Copy subdirectory files to home directory
echo "Installing subdirectory files..."
for subdir in "${subdir_array[@]}"; do
    # Check if subdirectory has files
    if [ -d "$subdir" ] && [ "$(ls -A "$subdir" 2>/dev/null)" ]; then
        cp -rf "$subdir/"* "$HOME/$subdir/" || fail "Failed to copy files to $HOME/$subdir/. Line $LINENO"
        # Update permissions for all files in the subdirectory
        find "$HOME/$subdir" -type f -exec chown "$USER":"$USER" {} \; || fail "Failed to update permissions for files in $HOME/$subdir. Line $LINENO"
        echo "Installed files in $subdir"
    fi
done

# Open main files for editing
echo "Opening main files for editing..."
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
echo "Installation complete! All bash configuration files and subdirectories have been installed."
