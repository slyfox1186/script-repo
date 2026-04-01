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
    local banner_msg current_dir_script local_script script_name
    script_name="optimize-jpg.py"
    local_script="/home/jman/Documents/ptemp/test/optimize-jpg.py"
    current_dir_script="$PWD/optimize-jpg.py"

    # Simple banner function to replace box_out_banner
    banner_msg="Optimizing Images: $PWD"

    # Ensure conda is activated
    if command -v conda &>/dev/null; then
        source ~/miniconda3/etc/profile.d/conda.sh
        conda activate base
    fi

    clear
    echo "=============================================="
    echo "$banner_msg"
    echo "=============================================="
    echo

    # Use the script in current directory if available, then test directory, then download
    if [[ -f "$current_dir_script" ]]; then
        echo "Using local script: $current_dir_script"
        script_name="$current_dir_script"
    elif [[ -f "$local_script" ]]; then
        echo "Using test directory script: $local_script"
        cp "$local_script" "$script_name"
    elif wget --timeout=2 --tries=2 -cqO "$script_name" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-jpg.py"; then
        echo "Downloaded script from repository"
    else
        printf "\n%s\n" "Failed to download the jpg optimization script."
        if command -v google_speech &>/dev/null; then
            google_speech "Failed to download the jpg optimization script." &>/dev/null
        fi
        return 1
    fi

    chmod +x "$script_name"
    LD_PRELOAD="libtcmalloc.so"
    if ! python "$script_name" -o; then
        printf "\n%s\n" "Failed to optimize images."
        if command -v google_speech &>/dev/null; then
            google_speech "Failed to optimize images." &>/dev/null
        fi
        # Don't delete on failure - leave it for debugging
    else
        # Always delete the script after successful completion
        rm -f "$script_name"
        echo "Script cleanup completed."
    fi
}

# Downsample image to 50% of the original dimensions using sharper settings
magick50() {
    local pic

    for pic in *.jpg; do
        convert "$pic" -colorspace sRGB -filter LanczosRadius -distort Resize 50% -colorspace sRGB "${pic%.jpg}-50.jpg"
    done
}
