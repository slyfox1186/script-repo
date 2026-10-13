#!/usr/bin/env bash
# FFmpeg, ImageMagick and Media Functions

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

# Downsample image to 50% of the original dimensions using sharper settings
magick50() (
    local pic

    shopt -s nullglob
    for pic in *.jpg; do
        [[ "$pic" == *-50.jpg ]] && continue
        magick "$pic" -colorspace sRGB -filter LanczosRadius -distort Resize 50% -colorspace sRGB "${pic%.jpg}-50.jpg" || return
    done
)

##########################
## SORT IMAGES BY WIDTH ##
##########################

# Prints WIDTHxHEIGHT and the full path of every JPG below the current folder, narrowest first.
jpgs() {
    find "$PWD" -type f -iname '*.jpg' -exec identify -format '%w\t%wx%h\t%d/%f\n' {} + | sort -t $'\t' -k1,1n | cut -f2-
}

#######################################
## IMAGEMAGICK LIST IMAGE DIMENSIONS ##
#######################################

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
