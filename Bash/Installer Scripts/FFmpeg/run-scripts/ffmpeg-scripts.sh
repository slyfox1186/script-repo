#!/usr/bin/env bash

# CREATE VARIABLES
parent_dir="$PWD"
tmp_dir="$(mktemp -d)"
scripts=("ffpb-loop" "ffpb-loop-paths" "convert-wmv-to-mp4")

# CREATE AND CD INTO A RANDOM DIRECTORY
cd "$tmp_dir" || exit 1

cat > "ffmpeg-scripts.txt" <<'EOF'
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/run-scripts/convert-x265-cuda-ffpb-loop.sh
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/run-scripts/convert-x265-cuda-ffpb-loop-paths.sh
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/run-scripts/convert-wmv-to-mp4.sh
EOF

# DOWNLOAD THE SCRIPTS FROM GITHUB
wget -qN - -i "ffmpeg-scripts.txt"

# RENAME THE SCRIPTS
sudo mv "convert-x265-cuda-ffpb-loop.sh" "ffpb-loop"
sudo mv "convert-x265-cuda-ffpb-loop-paths.sh" "ffpb-loop-paths"
sudo mv "convert-wmv-to-mp4.sh" "convert-wmv-to-mp4"

# MOVE THE SCRIPTS TO THE ORIGINAL DIRECTORY THE SCRIPT WAS EXECUTED FROM
sudo mv "${scripts[@]}" "$parent_dir"

# CD BACK INTO THE ORIGINAL DIRECTORY
cd "$parent_dir" || exit 1

# CHANGE THE FILE PERMISSIONS OF EACH SCRIPT
for script in "${scripts[@]}"
do
    sudo chown "$USER":"$USER" -R "$script"
    sudo chmod a+rwx -R "$script"
done

# DELETE THIS SCRIPT and THE RANDOM TEMP DIRECTORY
[[ -f "ffmpeg-scripts.txt" ]] && sudo rm "ffmpeg-scripts.txt"
[[ -d "$tmp_dir" ]] && sudo rm -fr "$tmp_dir"
