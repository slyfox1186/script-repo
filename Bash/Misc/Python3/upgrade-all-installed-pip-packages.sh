#!/usr/bin/env bash

# Create a temporary file
file=$(mktemp)

# Store the requirements in the temporary file
pip freeze > "$file"

# Install packages using the temporary requirements file
if ! pip install --upgrade -r "$file"; then
    clear
    pip install --break-system-packages --upgrade -r "$file"
fi

# Delete the temporary file
rm "$file"
