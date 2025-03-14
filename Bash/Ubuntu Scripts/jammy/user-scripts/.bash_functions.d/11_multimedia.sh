#!/usr/bin/env bash
# FFmpeg and Multimedia Functions

## FFMPEG COMMANDS ##

ffdl() {
    clear
    wget --show-progress -cqO "ff.sh" "https://ffdl.optimizethis.net"
    ./ff.sh
    sudo rm ff.sh
    clear; ls -1AhFv --color --group-directories-first
}

ffs() {
    wget --show-progress -cqO "https://raw.githubusercontent.com/slyfox1186/ffmpeg-build-script/main/build-ffmpeg.sh"
    clear
    ffr build-ffmpeg.sh
}

ffstaticdl() {
    if wget --connect-timeout=2 --tries=2 --show-progress -cqO ffmpeg-n7.0.tar.xz https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n7.0-latest-linux64-lgpl-7.0.tar.xz; then
        mkdir ffmpeg-n7.0
        tar -Jxf ffmpeg-n7.0.tar.xz -C ffmpeg-n7.0 --strip-components 1
        cd ffmpeg-n7.0/bin || exit 1
        sudo cp -f ffmpeg ffplay ffprobe /usr/local/bin/
        clear
        ffmpeg -version
    else
        echo "Downloading the static FFmpeg binaries failed!"
        return 1
    fi
}

ffr() {
    bash "$1" --build --enable-gpl-and-non-free --latest
}

ffrv() {
    bash -v "$1" --build --enable-gpl-and-non-free --latest
}

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
    LD_PRELOAD="libtcmalloc.so"
    if ! python3 optimize-jpg.py -o; then
        printf "\n%s\n" "Failed to optimize images."
        if command -v google_speech &>/dev/null; then
            google_speech "Failed to optimize images." &>/dev/null
        fi
        sudo rm -f "optimize-jpg.py"
    else
        sudo rm -f "optimize-jpg.py"
        exit
    fi
}

# Downsample image to 50% of the original dimensions using sharper settings
magick50() {
    local pic

    for pic in *.jpg; do
        convert "$pic" -colorspace sRGB -filter LanczosRadius -distort Resize 50% -colorspace sRGB "${pic%.jpg}-50.jpg"
    done
}