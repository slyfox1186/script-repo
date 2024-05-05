#!/usr/bin/env bash

# Define the directory for global npm packages
NPM_GLOBAL_DIR="$HOME/.npm-global"

# Create the directory if it doesn't exist
mkdir -p $NPM_GLOBAL_DIR

# Configure npm to use the new directory for global installations
npm config set prefix "$NPM_GLOBAL_DIR"

# Check if the PATH is already set in .bashrc
if ! grep -q "export PATH=$NPM_GLOBAL_DIR/bin:\$PATH" "$HOME/.bashrc"; then
  # Add the new directory to PATH in the .bashrc file
  echo "export PATH=$NPM_GLOBAL_DIR/bin:\$PATH" >> "$HOME/.bashrc"
fi

# Source the .bashrc to update the current session
source "$HOME/.bashrc"

echo "npm is configured to use $NPM_GLOBAL_DIR for global packages without sudo."
echo "The PATH variable is updated in .bashrc, please restart your terminal for changes to take effect."
