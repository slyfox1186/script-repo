#!/usr/bin/env bash

# Create variables
parent_dir="$PWD"
tmp_dir=$(mktemp -d)
scripts=("loop.sh" "loop-paths.sh" "wmv-to-mp4.sh")

# Prompt the user with choices
echo "Please select an option:"
echo "1. Download all scripts stored in the file created by the cat command"
echo "2. Download only the file 'loop.sh (AKA convert-x265-cuda-ffpb-loop.sh)' script"
echo "3. Download only the file 'loop-paths.sh (AKA convert-x265-cuda-ffpb-loop-paths.sh)' script"
echo "4. Download only the file 'wmv-to-mp4.sh (AKA convert-wmv-to-mp4.sh)' script"
echo "5. Exit script"

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        # Download all scripts
        selected_scripts=("${scripts[@]}")
        ;;
    2)
        # Download only 'loop.sh' script
        selected_scripts=("loop.sh")
        ;;
    3)
        # Download only 'loop-paths.sh' script
        selected_scripts=("loop-paths.sh")
        ;;
    4)
        # Download only 'wmv-to-mp4.sh' script
        selected_scripts=("wmv-to-mp4.sh")
        ;;
    5)
        # Exit the script
        echo "Exiting the script."
        exit 0
        ;;
    *)
        # Invalid choice
        echo "Invalid choice. Exiting the script."
        exit 1
        ;;
esac

# Create and cd into a random directory
cd "$tmp_dir" || exit 1

cat > "ffmpeg-scripts.txt" <<'EOF'
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/run-scripts/convert-x265-cuda-ffpb-loop.sh
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/run-scripts/convert-x265-cuda-ffpb-loop-paths.sh
https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/run-scripts/convert-wmv-to-mp4.sh
EOF

# Download the selected scripts from github
wget -qN - -i "ffmpeg-scripts.txt"

# Rename the scripts
for script in "${selected_scripts[@]}"; do
    case $script in
        "loop.sh")
            mv "convert-x265-cuda-ffpb-loop.sh" "loop.sh"
            ;;
        "loop-paths.sh")
            mv "convert-x265-cuda-ffpb-loop-paths.sh" "loop-paths.sh"
            ;;
        "wmv-to-mp4.sh")
            mv "convert-wmv-to-mp4.sh" "wmv-to-mp4.sh"
            ;;
    esac
done

# Execute chmod 755 on each script
for file in "${selected_scripts[@]}"; do
    chmod 755 "$file"
done

# Execute chown and change the file ownership to the user that is currently logged in
for file in "${selected_scripts[@]}"; do
    chown "$USER":"$USER" "$file"
done

# Move all the scripts to the script's directory
mv "${selected_scripts[@]}" "$parent_dir"

# Cd back into the original directory
cd "$parent_dir" || exit 1

# Remove any leftover temp files and directories
rm -fr "$tmp_dir"
