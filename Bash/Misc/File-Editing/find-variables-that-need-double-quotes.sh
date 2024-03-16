#!/usr/bin/env bash

# Validate input
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_file>"
    exit 1
fi

# Define file paths
input="$1"
results="/tmp/match_results.txt"

# Check file existence
if [ ! -f "$input" ]; then
    echo "File does not exist: $input"
    exit 1
fi

# Prepare the results file
> "$results"

# Initialize line number
line_number=0

# Process each line
while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number++))
    # Check the line for the pattern
    if echo "$line" | grep -P '(?<!")\$' | grep -vP '\".*\$.*\"' >/dev/null; then
        # Trim leading spaces and results to the file
        trimmed_line=$(echo "$line" | sed 's/^[ \t]*//')
        echo "Line $line_number: $trimmed_line" >> "$results"
    fi
done < "$input"

if command -v batcat &>/dev/null; then
    VIEWER="batcat"
elif command -v bat &>/dev/null; then
    VIEWER="bat"
else
    VIEWER="cat"
fi

# Open the store file using the bat or cat command
"$VIEWER" "$results"

echo
echo "Results stored in: $results"
