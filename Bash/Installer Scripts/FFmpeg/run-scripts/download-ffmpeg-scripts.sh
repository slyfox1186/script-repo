#!/usr/bin/env bash

# Create variables
parent_dir="$PWD"
temp_file=$(mktemp)
scripts=(loop.sh loop-paths.sh wmv-to-mp4.sh)

# Prompt the user with choices
echo "Please select the script(s) to download:"
echo "1. All"
echo "2. loop.sh"
echo "3. loop-paths.sh"
echo "4. wmv-to-mp4.sh"
echo "5. Exit"

read -p "Enter your choice (1-5): " choice

case "$choice" in
    1)  # Download all scripts
        selected_scripts=("${scripts[@]}")
        ;;
    2)  # Download only 'loop.sh' script
        selected_scripts=("loop.sh")
        ;;
    3)  # Download only 'loop-paths.sh' script
        selected_scripts=("loop-paths.sh")
        ;;
    4)  # Download only 'wmv-to-mp4.sh' script
        selected_scripts=("wmv-to-mp4.sh")
        ;;
    5)  # Exit the script
        echo "Exiting the script."
        exit 0
        ;;
    *)  # Invalid choice
        echo "Invalid choice. Exiting the script."
        exit 1
        ;;
esac

cat > "$temp_file" <<'EOF'
https://ffdl-loop.optimizethis.net
https://ffdl-loop-paths.optimizethis.net
https://ffdl-wmv.optimizethis.net
EOF

# Download the selected scripts from github
wget --show-progress -qN - -i "$temp_file"

# Rename the scripts
for script in "${selected_scripts[@]}"; do
    case $script in
        "loop.sh")
            mv "cuda-ffpb-loop-x265.sh" "loop.sh"
            ;;
        "loop-paths.sh")
            mv "cuda-ffpb-loop-paths-x265.sh" "loop-paths.sh"
            ;;
    esac
done

# Execute chmod 755 on each script
for file in "${selected_scripts[@]}"; do
    chmod 644 "$file"
done

# Execute chown and change the file ownership to the user that is currently logged in
for file in "${selected_scripts[@]}"; do
    chown "$USER:$USER" "$file"
done

# Move all the scripts to the script's directory
mv "${selected_scripts[@]}" "$parent_dir"

# Cd back into the original directory
cd "$parent_dir" || exit 1

# Remove any leftover temp files and directories
rm -f "$temp_file"
