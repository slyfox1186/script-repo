#!/usr/bin/env bash

# Set the output file extension
ext="mp4"

# Define the arrays
filenames=(
    ""
    ""
    ""
)

urls=(
    ""
    ""
    ""
)

paths=(
    ""
    ""
    ""
)

# Create the output file
random=$(mktemp)
output_file="${random}.sh"
cat > "$output_file" <<EOL
for i in {0..2}; do
    cd "${paths[i]}" || exit 1
    aria2c --conf-path="$HOME/.aria2/aria2.conf" --out="${filenames[i]}.${ext}" '${urls[i]}'
done
EOL

# Execute the output file
if bash "$output_file"; then
    google_speech "Batch video download completed." &>/dev/null
else
    google_speech "Batch video download failed." &>/dev/null
fi

# Delete the temporary file
rm "$output_file"
