#!/usr/bin/env bash

clear

# CREATE VARIABLES
cwd="${PWD}"
tmp_dir="$(mktemp -d)"
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'

# CREATE AND CD INTO A RANDOM DIRECTORY
cd "${tmp_dir}" || exit 1

# DOWNLOAD THE SCRIPTS FROM GITHUB
curl -A "${user_agent}" -m 10 -Lso 'imow' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-and-overwrite.sh'

# MOVE THE SCRIPTS TO THE ORIGINAL DIRECTORY THE SCRIPT WAS EXECUTED FROM
sudo mv 'imow' "${cwd}"

# DELETE THE RANDOM DIRECTORY
sudo rm -fr "${tmp_dir}"

# CD BACK INTO THE ORIGINAL DIRECTORY
cd "${cwd}" || exit 1

# CHANGE THE FILE PERMISSIONS OF EACH SCRIPT
sudo chown "${USER}":"${USER}" 'imow'
sudo chmod +rwx 'imow'
