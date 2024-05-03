#!/usr/bin/env bash
set -eo pipefail

## Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/build-dmd.sh
## Purpose: Install DLang D Compiler (DMD)
## Date: 05.03.24
## Script version 1.1

echo "Installing DMD -- version latest"
echo "======================================"
echo

# Fetch and store the latest dmd version
echo 'Fetching the latest DMD version.'
version=$(curl -fsS "https://downloads.dlang.org/releases/LATEST")

# Check if version is captured
if [ -z "$version" ]; then
    printf "Failed to capture DLang version.\n\n"
    exit 1
fi

# Download the install script with retries using different user agents
echo "Downloading the install script for DMD version $version."
download_success=0

clear
set -x
if ! wget --show-progress -cqO "$PWD/dmd-installer.sh" "https://dlang.org/install.sh"; then
    printf "Failed to download the install script after retries.\n\n"
    rm -f "$PWD/dmd-installer.sh"
    exit 1
fi

# Make the script executable
echo "Setting script permissions."
chmod +x "$PWD/dmd-installer.sh"

# Run the script and redirect verbose output to /dev/null
echo "Installing DMD version $version"
if ! sudo bash "$PWD/dmd-installer.sh" install &>/dev/null; then
    printf "\nInstallation of DMD failed.\n\n"
    rm -f "$PWD/dmd-installer.sh"
    exit 1
fi

# Add dub to the users .bashrc file
cat >> "$HOME/.bashrc" <<EOF

export PATH="\$PATH:\$HOME/dlang/dmd-$version/linux/bin64"
EOF

# Activate dmd
source "$HOME/.bashrc"
source "$HOME/dlang/dmd-$version/activate"

# Delete the install script
#rm -f "$PWD/dmd-installer.sh"

echo
echo "Make sure to star this repository to show your support!"
echo "https://github.com/slyfox1186/script-repo"
echo
