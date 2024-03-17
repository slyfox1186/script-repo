#!/usr/bin/env bash

INPUT_FILE="/tmp/folder-paths.txt"
OUPUT_FOLDER="/path/to/output/folder"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
YELLOW='\033[0;33m'

cat > "$INPUT_FILE" <<'EOF'
/folders/to/move
/folders/to/move
EOF

process_file_path() {
    local file_path=$1

    echo -e "$CYANProcessing file$YELLOW: $PURPLE$file_path$NC"

    if sudo mv "$file_path" "$OUPUT_FOLDER"; then
        echo -e "$GREEN[LOG]$NC Command executed successfully\\n"
    else
        echo -e "$RED[ERROR]$NC Failed to execute command\\n" >&2
    fi
}

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File '$INPUT_FILE' not found." >&2
    exit 1
fi

while IFS= read -r line; do
    if [ -z "$line" ]; then
        continue
    fi
    process_file_path "$line"
done < "$INPUT_FILE"

echo "Script completed."
