#!/usr/bin/env bash
# FFmpeg, ImageMagick and Media Functions

ffdl() {
    clear
    wget --show-progress -cqO "ff.sh" "https://ffdl.optimizethis.net"
    ./ff.sh
    sudo rm ff.sh
    clear; ls -1AhFv --color --group-directories-first
}

ffs() {
    local repo_dir="$HOME/.local/share/ffmpeg-build-script" repo_status
    local repo_url='https://github.com/slyfox1186/ffmpeg-build-script.git'

    if [[ -e "$repo_dir" ]]; then
        if [[ ! -d "$repo_dir/.git" ]] || [[ $(git -C "$repo_dir" remote get-url origin) != "$repo_url" ]]; then
            printf 'Refusing to replace an unrelated directory: %s\n' "$repo_dir" >&2
            return 1
        fi
        repo_status=$(git -C "$repo_dir" status --porcelain) || return
        if [[ -n "$repo_status" ]]; then
            printf 'Local changes exist in %s; leaving them untouched.\n' "$repo_dir" >&2
            return 1
        fi
        git -C "$repo_dir" pull --ff-only || return
    else
        mkdir -p -- "${repo_dir%/*}" || return
        git clone -- "$repo_url" "$repo_dir" || return
    fi
    ffr "$repo_dir/build-ffmpeg.py" "$@"
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

## FFMPEG COMMANDS ##

_run_ffmpeg_builder() {
    local mode="$1" script="${2-}"
    local builder_python="$HOME/miniconda3/envs/install-ffmpeg/bin/python"
    if (($# < 2)) || [[ ! -r "$script" ]]; then
        printf 'Usage: ffr|ffrv PATH_TO_BUILD_SCRIPT [OPTIONS...]\n' >&2
        return 1
    fi
    shift 2
    if (($# == 0)); then
        set -- --build --enable-gpl-and-non-free --latest
    fi
    case "$script" in
        *.py)
            if [[ ! -x "$builder_python" ]]; then
                printf 'FFmpeg build interpreter is missing: %s\n' "$builder_python" >&2
                return 1
            fi
            if [[ "$mode" == verbose ]]; then
                PYTHONVERBOSE=1 "$builder_python" "$script" "$@"
            else
                "$builder_python" "$script" "$@"
            fi ;;
        *)
            if [[ "$mode" == verbose ]]; then
                bash -v "$script" "$@"
            else
                bash "$script" "$@"
            fi ;;
    esac
}

ffr() { _run_ffmpeg_builder normal "$@"; }
ffrv() { _run_ffmpeg_builder verbose "$@"; }

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

# Downsample image to 50% of the original dimensions using sharper settings
magick50() {
    local pic

    for pic in *.jpg; do
        convert "$pic" -colorspace sRGB -filter LanczosRadius -distort Resize 50% -colorspace sRGB "${pic%.jpg}-50.jpg"
    done
}

##########################
## SORT IMAGES BY WIDTH ##
##########################

jpgs() {
    local output_file
    output_file=$(mktemp) || return 1
    find . -type f -iname '*.jpg' -exec identify -format " $PWD/%f: %wx%h " {} \; > "$output_file"
    sed 's/\s\//\n\//g' "$output_file" | sort -h
    rm -f -- "$output_file"
}

###################################
## FFPROBE LIST IMAGE DIMENSIONS ##
###################################

ffp() {
    find "$PWD" -type f -iname '*.jpg' -exec sh -c 'for image do identify -format "%wx%h" "$image"; printf " %s\n" "$image"; done' sh {} + > 00-pic-sizes.txt
}

## MediaInfo
mi() {
    local file

    if [[ -z "$1" ]]; then
        ls -1AhFv --color --group-directories-first
        echo
        read -r -p "Please enter the relative FILE path: " file
        echo
        mediainfo "$file"
    else
        mediainfo "$1"
    fi
}
