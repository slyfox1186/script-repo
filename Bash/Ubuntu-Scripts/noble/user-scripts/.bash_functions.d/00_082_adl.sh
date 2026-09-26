#!/usr/bin/env bash

############
## ARIA2C ##
############

adl() {
local file url

if [[ "$#" -ne 2 ]]; then
    echo "Error: Two arguments are required: output file and download URL"
    return 1
fi

if ! command -v aria2c &>/dev/null; then
    echo "aria2c is missing and will be installed."
    sleep 3
    bash <(curl -fsSL "https://aria2.optimizethis.net")
fi

file="$1"

# Check if the file extension is missing and append '.mp4' if needed
if [[ "$file" != *.mp4 ]]; then
    file+=".mp4"
fi

url="$2"

if [[ ! -f "$HOME/.aria2/aria2.conf" ]]; then
    mkdir -p "$HOME/.aria2"
    if ! wget -cqO "/tmp/create-aria2-folder.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/Networking/create-aria2-folder.sh"; then
        echo "Failed to download the aria2.conf installer script."
        return 1
    fi
    if ! bash "/tmp/create-aria2-folder.sh"; then
        echo "Failed to execute: /tmp/create-aria2-folder.sh"
        return 1
    fi
fi
    aria2c --conf-path="$HOME/.aria2/aria2.conf" --out="$file" "$url"
}
