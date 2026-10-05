#!/usr/bin/env bash

# GitHub raw base URL
base_url="https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Arch-Linux-Scripts"

# Files to install directly into $HOME
home_files=(".bashrc" ".bash_aliases" ".bash_functions")

# Modular function scripts (.bash_functions.d/)
functions_d=(
    "00_master_functions.sh"
    "01_gui_apps.sh"
    "02_filesystem.sh"
    "03_text_processing.sh"
    "04_compression.sh"
    "05_process_management.sh"
    "06_dev_tools.sh"
    "07_file_analysis.sh"
    "08_security.sh"
    "09_networking.sh"
    "10_multimedia.sh"
    "11_utilities.sh"
    "12_database.sh"
    "13_docker.sh"
    "14_package_manager.sh"
    "15_redis_and_npm.sh"
    "16_other.sh"
    "17_sed.sh"
    "18_grep.sh"
    "19_enhanced_utilities.sh"
    "20_optimized_functions.sh"
    "21_claude_code.sh"
    "22_systemd.sh"
    "23_ssh.sh"
)

# Modular alias scripts (.bash_aliases.d/)
aliases_d=(
    "01_sudo_aliases.sh"
    "02_system_control.sh"
    "03_network.sh"
    "04_docker.sh"
    "05_filesystem.sh"
    "06_package_management.sh"
    "07_editors.sh"
    "08_claude_code.sh"
    "09_execute_scripts.sh"
)

fail() {
    echo -e "\\n[ERROR] $1\\n"
    read -p "Press enter to exit."
    exit 1
}

# Ensure wget is installed
if ! pacman -Q wget &>/dev/null; then
    sudo pacman -S --needed --noconfirm wget
    clear
fi

td=$(mktemp -d)
cd "$td" || exit 1

echo "Downloading dotfiles..."

# Download home-level files
for f in "${home_files[@]}"; do
    wget -qN "${base_url}/${f}" -O "$f" || fail "Failed to download $f"
done

# Download .bash_functions.d/ scripts
mkdir -p .bash_functions.d
for f in "${functions_d[@]}"; do
    wget -qN "${base_url}/.bash_functions.d/${f}" -O ".bash_functions.d/$f" || fail "Failed to download .bash_functions.d/$f"
done

# Download .bash_aliases.d/ scripts
mkdir -p .bash_aliases.d
for f in "${aliases_d[@]}"; do
    wget -qN "${base_url}/.bash_aliases.d/${f}" -O ".bash_aliases.d/$f" || fail "Failed to download .bash_aliases.d/$f"
done

echo "Installing files..."

# Create target directories
mkdir -p "$HOME/.bashrc.d" "$HOME/.bash_functions.d" "$HOME/.bash_aliases.d"

# Install home-level files
for f in "${home_files[@]}"; do
    cp -f "$f" "$HOME/" || fail "Failed to copy $f to $HOME"
    chown "$USER":"$USER" "$HOME/$f"
done

# Install .bash_functions.d/ scripts
for f in "${functions_d[@]}"; do
    cp -f ".bash_functions.d/$f" "$HOME/.bash_functions.d/" || fail "Failed to copy .bash_functions.d/$f"
    chown "$USER":"$USER" "$HOME/.bash_functions.d/$f"
done

# Install .bash_aliases.d/ scripts
for f in "${aliases_d[@]}"; do
    cp -f ".bash_aliases.d/$f" "$HOME/.bash_aliases.d/" || fail "Failed to copy .bash_aliases.d/$f"
    chown "$USER":"$USER" "$HOME/.bash_aliases.d/$f"
done

rm -rf "$td"

echo -e "\\nAll dotfiles installed successfully!"
echo "Run 'source ~/.bashrc' or open a new terminal to apply changes."
