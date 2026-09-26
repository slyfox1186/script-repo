#!/usr/bin/env bash

dlfs() {
    local file
    local -a scripts
    clear

    wget --show-progress -qN - -i "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/favorite-installer-scripts.txt"

    scripts=(build-ffmpeg build-all-git-safer build-all-gnu-safer build-magick)

    for file in "${scripts[@]}"; do
        chown -R "$USER:$USER" "$file"
        chmod -R 744 "$PWD" "$file"
        if [[ $file == "build-all-git-safer" || $file == "build-all-gnu-safer" ]]; then
            mv "$file" "${file%-safer}"
        fi
    done
    rm -f -- "favorite-installer-scripts.txt"

    clear
    ls -1AhFv --color --group-directories-first
}
