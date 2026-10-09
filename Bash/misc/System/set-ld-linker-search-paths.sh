#!/usr/bin/env bash

filename="/etc/ld.so.conf.d/custom-ld-paths.conf"

if [[ "$EUID" -ne 0 ]]; then
    echo "You must run this script as root or with sudo."
    exit 1
fi

# Array of paths to add to the ld linker, ordered by importance
paths=(
    # CUDA paths
    "/usr/local/cuda/lib64"
    "/usr/local/cuda/lib"
    "/usr/local/cuda/targets/x86_64-linux/lib"
    "/opt/cuda/lib64"
    "/opt/cuda/lib"
    "/opt/cuda/targets/x86_64-linux/lib"

    # Local paths
    "/usr/local/lib"
    "/usr/local/lib64"
    "/usr/local/lib/x86_64-linux-gnu"
    "/usr/local/lib64/x86_64-linux-gnu"

    # System paths
    "/usr/lib"
    "/usr/lib64"
    "/usr/lib/x86_64-linux-gnu"
    "/lib"
    "/lib64"
    "/lib/x86_64-linux-gnu"
)

# Check if each path exists and is a directory
valid_paths=()
for path in "${paths[@]}"; do
    if [[ -d "$path" ]]; then
        valid_paths+=("$path")
    fi
done

# Write valid paths to the configuration file
echo "# Custom LD library paths" > "$filename"
printf "%s\n" "${valid_paths[@]}" >> "$filename"

# Update the ld cache
ldconfig
