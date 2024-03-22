#!/usr/bin/env bash

clear

# Create variables
cwd="${PWD}"
tmp_dir="$(mktemp -d)"
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'

# Create and cd into a random directory
cd "${tmp_dir}" || exit 1

# Download the scripts from github
curl -A "${user_agent}" -m 10 -Lso 'imow' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-and-overwrite.sh'

# Move the scripts to the original directory the script was executed from
sudo mv 'imow' "${cwd}"

# Delete the random directory
sudo rm -fr "${tmp_dir}"

# Cd back into the original directory
cd "${cwd}" || exit 1

# Change the file permissions of each script
sudo chown "${USER}":"${USER}" 'imow'
sudo chmod +rwx 'imow'
