#!/usr/bin/env bash

# Output file name
output_file="mirror-results.txt"
temp_file="temp.txt"

# URL to fetch the mirror list from
url="https://archlinux.org/mirrorlist/?ip_version=6"

# Download the mirror list using curl and save it to a temporary file
curl -fsS "$url" > "$temp_file"

# Clear the output file
echo -n "" > "$output_file"

# Extract the date from the downloaded file
generated_date=$(grep -oP '## Generated on \K\d{4}-\d{2}-\d{2}' "$temp_file")

# Write the comments at the top of the output file
echo "##" >> "$output_file"
echo "## Arch Linux repository mirrorlist" >> "$output_file"
echo "## Generated on $generated_date" >> "$output_file"
echo "##" >> "$output_file"
echo "" >> "$output_file"

# Flag to track if inside the United States section
inside_us_section=false

# Temporary file to store the filtered lines
filtered_file="filtered.txt"

# Read the downloaded file line by line
while IFS= read -r line; do
    # Check if the line contains "## United States"
    if [[ $line == "## United States" ]]; then
        inside_us_section=true
        echo "$line" >> "$filtered_file"
    # Check if the line starts with "##" and is not "## United States"
    elif [[ $line == \#\#* && $line != "## United States" ]]; then
        inside_us_section=false
    fi
    
    # If inside the United States section, write the line to the filtered file
    if $inside_us_section; then
        echo "$line" >> "$filtered_file"
    fi
done < "$temp_file"

# Remove duplicate lines from the filtered file and append to the output file
uniq "$filtered_file" >> "$output_file"

# Remove the temporary files
rm "$temp_file"
rm "$filtered_file"

echo "Output file '$output_file' created successfully."
