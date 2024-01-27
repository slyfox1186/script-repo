#!/usr/bin/env bash

# Define the folder where the images are located (current directory by default).
image_folder="./output"

# Check if the user has provided a prefix, otherwise use a default value.
if [ -z "$1" ]; then
    read -p 'Enter the prefix for each file: ' prefix
else
    prefix="$1"
fi

# Ensure the folder exists and is accessible.
if [ ! -d "$image_folder" ]; then
    printf "%s\n\n" "Error: The specified folder '$image_folder' does not exist."
    exit 1
fi

# Counter for numbering the files.
cnt=1

# Loop through all image files in the folder.
for file in "$image_folder"/*.{jpg,jpeg,gif,png,ico,icon}
do
    if [ -f "$file" ]; then
        # Determine the file extension.
        ext="${file##*.}"

        # Generate the new filename.
        new_filename="${prefix}-$(printf "%02d" $cnt).$ext"

        # Rename the file.
        mv "$file" "$image_folder/$new_filename"

        # Increment the cnter.
        cnt=$((cnt + 1))
    fi
done

# Print a message when the renaming is complete.
printf "\n%s\n\n" "Batch renaming of images in '$image_folder' is complete."
