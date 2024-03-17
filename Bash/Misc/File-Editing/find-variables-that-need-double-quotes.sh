#!/usr/bin/env bash

    echo "Usage: $0 <path_to_file>"
    exit 1
fi

input="$1"
results="/tmp/match_results.txt"

if [ ! -f "$input" ]; then
    echo "File does not exist: $input"
    exit 1
fi

> "$results"

line_number=0

while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number++))
    if echo "$line" | grep -P '(?<!")\$' | grep -vP '\".*\$.*\"' >/dev/null; then
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

"$VIEWER" "$results"

echo
echo "Results stored in: $results"
