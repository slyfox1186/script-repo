#!/usr/bin/env bash

## IMAGEMAGICK ##

imow() {
    if wget --timeout=2 --tries=2 -cqO "optimize-jpg.py" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-jpg.py"; then
        clear
        box_out_banner "Optimizing Images: $PWD"
        echo
    else
        printf "\n%s\n" "Failed to download the jpg optimization script."
        if command -v google_speech &>/dev/null; then
            google_speech "Failed to download the jpg optimization script." &>/dev/null
        fi
    fi
    sudo chmod +x "optimize-jpg.py"
    source "$HOME/python-venv/myenv/bin/activate"
    if ! LD_PRELOAD="libtcmalloc.so" python3 optimize-jpg.py -o; then
        printf "\n%s\n" "Failed to optimize images."
        if command -v google_speech &>/dev/null; then
            google_speech "Failed to optimize images." &>/dev/null
        fi
        sudo rm -f "optimize-jpg.py"
    else
        sudo rm -f "optimize-jpg.py"
        return 0
    fi
}
