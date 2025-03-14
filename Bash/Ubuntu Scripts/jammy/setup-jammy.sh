#!/bin/bash
# Jammy bash configuration setup script

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_SCRIPTS_DIR="$SCRIPT_DIR/user-scripts"

# Target directories - defaults to user's home directory
TARGET_DIR="${1:-$HOME}"

# Banner function
print_banner() {
    echo -e "${BLUE}=======================================${NC}"
    echo -e "${GREEN}  Jammy Bash Configuration Setup${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo
}

# Check if script is run with sudo/root
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${RED}This script should not be run as root or with sudo.${NC}"
        echo -e "${YELLOW}Run it as a regular user.${NC}"
        exit 1
    fi
}

# Create backup of existing files
create_backup() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_dir="$TARGET_DIR/.bash_backup_$timestamp"
    
    echo -e "${YELLOW}Creating backup of existing bash configuration...${NC}"
    mkdir -p "$backup_dir"
    
    # Backup existing files
    [[ -f "$TARGET_DIR/.bashrc" ]] && cp "$TARGET_DIR/.bashrc" "$backup_dir/"
    [[ -f "$TARGET_DIR/.bash_aliases" ]] && cp "$TARGET_DIR/.bash_aliases" "$backup_dir/"
    [[ -f "$TARGET_DIR/.bash_functions" ]] && cp "$TARGET_DIR/.bash_functions" "$backup_dir/"
    
    # Backup existing directories
    [[ -d "$TARGET_DIR/.bashrc.d" ]] && cp -r "$TARGET_DIR/.bashrc.d" "$backup_dir/"
    [[ -d "$TARGET_DIR/.bash_aliases.d" ]] && cp -r "$TARGET_DIR/.bash_aliases.d" "$backup_dir/"
    [[ -d "$TARGET_DIR/.bash_functions.d" ]] && cp -r "$TARGET_DIR/.bash_functions.d" "$backup_dir/"
    
    echo -e "${GREEN}Backup created at: $backup_dir${NC}"
}

# Install configuration files
install_configuration() {
    echo -e "${YELLOW}Installing Jammy bash configuration files...${NC}"
    
    # Create directories if they don't exist
    mkdir -p "$TARGET_DIR/.bashrc.d"
    mkdir -p "$TARGET_DIR/.bash_aliases.d"
    mkdir -p "$TARGET_DIR/.bash_functions.d"
    
    # Copy main files with modifications
    for file in .bashrc .bash_aliases .bash_functions; do
        # Replace the hard-coded paths with the actual target directory
        sed "s|export JAMMY_BASE=\"\$HOME/tmp/user_scripts/jammy\"|export JAMMY_BASE=\"$SCRIPT_DIR\"|g" \
            "$USER_SCRIPTS_DIR/$file" > "$TARGET_DIR/$file"
        chmod +x "$TARGET_DIR/$file"
    done
    
    # Copy module directories
    cp -r "$USER_SCRIPTS_DIR/.bashrc.d/"* "$TARGET_DIR/.bashrc.d/"
    cp -r "$USER_SCRIPTS_DIR/.bash_aliases.d/"* "$TARGET_DIR/.bash_aliases.d/"
    cp -r "$USER_SCRIPTS_DIR/.bash_functions.d/"* "$TARGET_DIR/.bash_functions.d/"
    
    echo -e "${GREEN}Configuration files installed successfully!${NC}"
}

# Create a source line that can be added to an existing .bashrc
create_source_line() {
    echo -e "${YELLOW}Creating source line for existing configurations...${NC}"
    echo
    echo -e "${GREEN}Add the following lines to your existing .bashrc if you prefer not to replace it:${NC}"
    echo
    echo "# Source Jammy Bash Configuration"
    echo "export JAMMY_BASE=\"$SCRIPT_DIR\""
    echo "export JAMMY_USER_SCRIPTS=\"\$JAMMY_BASE/user-scripts\""
    echo "if [[ -f \"\$JAMMY_USER_SCRIPTS/.bashrc\" ]]; then"
    echo "    source \"\$JAMMY_USER_SCRIPTS/.bashrc\""
    echo "fi"
    echo
}

# Main function
main() {
    print_banner
    check_sudo
    
    echo -e "${YELLOW}This script will install the Jammy bash configuration to: $TARGET_DIR${NC}"
    echo -e "${RED}Existing configurations will be backed up before installation.${NC}"
    echo
    read -p "Do you want to continue? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_backup
        install_configuration
        create_source_line
        
        echo
        echo -e "${GREEN}Installation complete!${NC}"
        echo -e "${YELLOW}To apply the changes, either start a new terminal session or run:${NC}"
        echo -e "${BLUE}source $TARGET_DIR/.bashrc${NC}"
    else
        echo -e "${YELLOW}Installation cancelled.${NC}"
    fi
}

# Run the main function
main