#!/usr/bin/env bash

# Create an array
scripts=(loop.sh loop_paths.sh wmv_to_mp4.sh)

# Prompt the user with choices
echo "Please select the script(s) to download:"
echo "1. All"
echo "2. loop.sh"
echo "3. loop_paths.sh"
echo "4. wmv_to_mp4.sh"
echo "5. Exit"

read -p "Enter your choice (1-5): " choice

case "$choice" in
    1)  # Download all scripts
        selected_scripts=("${scripts[@]}")
        wget -cqO "loop.sh" "https://ffdl-loop.optimizethis.net"
        wget -cqO "loop_paths.sh" "https://ffdl-loop-paths.optimizethis.net"
        wget -cqO "wmv_to_mp4.sh" "https://ffdl-wmv.optimizethis.net"
        ;;
    2)  # Download only 'loop.sh' script
        selected_scripts=("loop.sh")
        wget -cqO "loop.sh" "https://ffdl-loop.optimizethis.net"
        ;;
    3)  # Download only 'loop_paths.sh' script
        selected_scripts=("loop_paths.sh")
        wget -cqO "loop_paths.sh" "https://ffdl-loop-paths.optimizethis.net"
        ;;
    4)  # Download only 'wmv_to_mp4.sh' script
        selected_scripts=("wmv_to_mp4.sh")
        wget -cqO "wmv_to_mp4.sh" "https://ffdl-wmv.optimizethis.net"
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

# Execute chmod 755 on each script
for script in "${selected_scripts[@]}"; do
    chmod 644 "$script"
done

# Execute chown and change the file ownership to the user that is currently logged in
for script in "${selected_scripts[@]}"; do
    chown "$USER:$USER" "$script"
done
