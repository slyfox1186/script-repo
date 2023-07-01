#!/bin/bash

clear

# Create and cd into a random directory
cd "$(mktemp --directory)" || exit 1

# Download the user scripts from GitHub
wget -qN - -i 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/shell/ffmpeg/run-scripts/ffmpeg-scripts.txt'

sudo chown "$USER":"$USER" -R convert-x265-cuda-ffpb.sh convert-x265-cuda-ffmpeg.sh
sudo chmod +rwx -R convert-x265-cuda-ffpb.sh convert-x265-cuda-ffpb.sh

mv convert-x265-cuda-ffpb.sh ffpb
mv convert-x265-cuda-ffmpeg.sh ffmpeg

# Remove the installer script itself
if [ -f "$0" ]; then
    sudo rm "$0"
fi
