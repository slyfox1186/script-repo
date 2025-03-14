#!/usr/bin/env bash
# Jammy User Scripts - Deploy modular bash files to user's home directory
# Author: slyfox1186 (https://github.com/slyfox1186/script-repo)
# Repository: https://github.com/slyfox1186/script-repo/tree/main/Bash/Ubuntu%20Scripts/jammy
# shellcheck disable=SC2155

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner function
box_out_banner() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 "$input_char"); do printf "-"; done)
    tput bold
    line="$(tput setaf 3)$line"
    space="${line//-/ }"
    echo " $line"
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    printf "| " ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" " |";
    printf "|" ; echo -n "$space" ; printf "%s\n" "|";
    echo " $line"
    tput sgr 0
}

# Information message
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Warning message
warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Error message
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create backup of existing files
create_backup() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_dir="$HOME/.bash_backup_$timestamp"
    
    info "Creating backup of existing bash configuration..."
    mkdir -p "$backup_dir"
    
    # Backup existing files
    [[ -f "$HOME/.bashrc" ]] && cp "$HOME/.bashrc" "$backup_dir/"
    [[ -f "$HOME/.bash_aliases" ]] && cp "$HOME/.bash_aliases" "$backup_dir/"
    [[ -f "$HOME/.bash_functions" ]] && cp "$HOME/.bash_functions" "$backup_dir/"
    
    # Backup existing directories (if they exist)
    [[ -d "$HOME/.bashrc.d" ]] && cp -r "$HOME/.bashrc.d" "$backup_dir/"
    [[ -d "$HOME/.bash_aliases.d" ]] && cp -r "$HOME/.bash_aliases.d" "$backup_dir/"
    [[ -d "$HOME/.bash_functions.d" ]] && cp -r "$HOME/.bash_functions.d" "$backup_dir/"
    
    info "Backup created at: $backup_dir"
}

# Deploy files from user-scripts to home directory
deploy_files() {
    info "Deploying modular bash files to home directory..."
    
    # Get the temporary directory where the script is running
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local USER_SCRIPTS_DIR="$SCRIPT_DIR/user-scripts"
    
    # If running via curl and user-scripts dir doesn't exist, clone the repo
    if [[ ! -d "$USER_SCRIPTS_DIR" ]]; then
        warn "User scripts directory not found. Downloading from GitHub..."
        
        # Create a temporary directory
        local TEMP_DIR=$(mktemp -d)
        pushd "$TEMP_DIR" > /dev/null
        
        # Clone the repository or download the files
        if command -v git > /dev/null; then
            git clone --depth 1 https://github.com/slyfox1186/script-repo.git
            USER_SCRIPTS_DIR="$TEMP_DIR/script-repo/Bash/Ubuntu Scripts/jammy/user-scripts"
        else
            # Fallback if git is not available
            curl -fsSL -o jammy.zip https://github.com/slyfox1186/script-repo/archive/refs/heads/main.zip
            unzip -q jammy.zip
            USER_SCRIPTS_DIR="$TEMP_DIR/script-repo-main/Bash/Ubuntu Scripts/jammy/user-scripts"
        fi
        
        # Validate that we have the files
        if [[ ! -d "$USER_SCRIPTS_DIR" ]]; then
            error "Failed to download the required files. Please check your internet connection."
            popd > /dev/null
            return 1
        fi
    fi
    
    # Create the directory structure
    mkdir -p "$HOME/.bashrc.d"
    mkdir -p "$HOME/.bash_aliases.d"
    mkdir -p "$HOME/.bash_functions.d"
    
    # Copy main files (without the Jammy path references)
    for file in .bashrc .bash_aliases .bash_functions; do
        # Create a clean version without Jammy-specific paths
        sed '/JAMMY_BASE/d; /JAMMY_USER_SCRIPTS/d; s|"$JAMMY_USER_SCRIPTS/|"$HOME/|g; s|"$BASHRC_DIR"|"$HOME/.bashrc.d"|g; s|"$BASH_ALIASES_DIR"|"$HOME/.bash_aliases.d"|g; s|"$BASH_FUNCTIONS_DIR"|"$HOME/.bash_functions.d"|g' \
            "$USER_SCRIPTS_DIR/$file" > "$HOME/$file"
        chmod +x "$HOME/$file"
    done
    
    # Copy module directories
    cp -r "$USER_SCRIPTS_DIR/.bashrc.d/"* "$HOME/.bashrc.d/"
    cp -r "$USER_SCRIPTS_DIR/.bash_aliases.d/"* "$HOME/.bash_aliases.d/"
    cp -r "$USER_SCRIPTS_DIR/.bash_functions.d/"* "$HOME/.bash_functions.d/"
    
    # Fix any remaining references to Jammy paths in the module files
    find "$HOME/.bashrc.d" "$HOME/.bash_aliases.d" "$HOME/.bash_functions.d" -type f -name "*.sh" -exec \
        sed -i 's|"$JAMMY_USER_SCRIPTS/|"$HOME/|g; s|"$JAMMY_BASE|"$HOME|g' {} \;
    
    # Make all scripts executable
    chmod +x "$HOME/.bashrc.d/"*.sh
    chmod +x "$HOME/.bash_aliases.d/"*.sh
    chmod +x "$HOME/.bash_functions.d/"*.sh
    
    # Clean up temporary directory if we created one
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        popd > /dev/null
        rm -rf "$TEMP_DIR"
    fi
    
    info "Modular bash files successfully deployed"
}

# Main function
main() {
    box_out_banner "Ubuntu Jammy Bash Configuration Install"
    
    echo "This script will install modular bash configuration files to your home directory."
    echo "Your existing configuration will be backed up before installation."
    echo
    read -p "Do you want to continue? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_backup
        deploy_files
        
        echo
        info "Installation complete!"
        warn "To apply the changes, either start a new terminal session or run:"
        echo -e "${BLUE}source $HOME/.bashrc${NC}"
    else
        warn "Installation cancelled."
    fi
}

# Run the main function
main