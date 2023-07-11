#!/bin/bash

clear

# CREATE VARIABLES
parent_dir="$PWD"
tmp_dir="$(mktemp -d)"

# CREATE AND CD INTO A RANDOM DIRECTORY
cd "$tmp_dir" || exit 1

# DOWNLOAD THE SCRIPTS FROM GITHUB
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/ffmpeg/run-scripts/ffmpeg-scripts.txt'

# RENAME THE SCRIPTS
sudo mv convert-x265-cuda-ffpb.sh ffpb
sudo mv convert-x265-cuda-ffmpeg.sh ffmpeg

# MOVE THE SCRIPTS TO THE ORIGINAL DIRECTORY THE SCRIPT WAS EXECUTED FROM
sudo mv ffpb ffmpeg "$parent_dir"

# CD BACK INTO THE ORIGINAL DIRECTORY
cd "$parent_dir" || exit 1

# DELETE THE RANDOM DIRECTORY
sudo rm -fr "$tmp_dir"

# CHANGE THE FILE PERMISSIONS OF EACH SCRIPT
sudo chown "$USER":"$USER" -R ffmpeg ffpb
sudo chmod +rwx -R ffmpeg ffpb

# UNSET THE SCRIPT VARIABLES
unset parent_dir tmp_dir

# REMOVE THE INSTALLER SCRIPT ITSELF
if [ -f "$0" ]; then
    sudo rm "$0"
fi
