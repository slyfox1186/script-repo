#!/usr/bin/env bash
# Shellcheck disable=SC2066,SC2068,SC2086,SC2162

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if required Python modules are installed
if ! python3 -c "import ffpb" &>/dev/null; then
    fail "Python module 'ffpb' is not installed. Please install it and try again."
    exit 1
fi

if ! python3 -c "import google_speech" &>/dev/null; then
    fail "Python module 'google_speech' is not installed. Please install it and try again."
    exit 1
fi

# Set the PATH variable
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# Install required packages
if command -v apt-get >/dev/null 2>&1; then
    # Debian-based distributions
    apt_packages=("bc" "ffmpegthumbnailer" "libffmpegthumbnailer-dev" "libsox-fmt-all" "python3-pip" "sox")
    missing_apt_pkgs=()

    # Loop through the array to find missing packages
    for pkg in "${apt_packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_apt_pkgs+=("$pkg")
        fi
    done

    if [ "${#missing_apt_pkgs[@]}" -gt 0 ]; then
        log "Installing: ${missing_apt_pkgs[@]}"
        echo
        sudo apt -y install "${missing_apt_pkgs[@]}" || fail "Failed to install required packages."
    fi
elif command -v pacman >/dev/null 2>&1; then
    # Arch Linux
    pacman_packages=("bc" "ffmpegthumbnailer" "libffmpegthumbnailer" "python-pip" "sox")
    missing_pacman_pkgs=()

    for pkg in "${pacman_packages[@]}"; do
        if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
            missing_pacman_pkgs+=("$pkg")
        fi
    done

    if [ "${#missing_pacman_pkgs[@]}" -gt 0 ]; then
        log "Installing: ${missing_pacman_pkgs[@]}"
        echo
        sudo pacman -Sy --noconfirm --needed "${missing_pacman_pkgs[@]}" || fail "Failed to install required packages."
    fi
else
    fail "Unsupported package manager. Please install the required packages manually."
fi

# Make sure there are videos available to convert
vid_test=$(find ./ -maxdepth 1 -type f \( -iname \*.mp4 -o -iname \*.mkv \) | xargs -0n1 | head -n1)

if [ -z "$vid_test" ]; then
    google_speech "No input videos were located." 2>/dev/null
    fail "No input videos were located."
fi

# Create a temporary output folder in the /tmp directory
random_dir=$(mktemp -d)

for vid in *.{mp4,mkv}; do
    vid_test="$(find ./ -maxdepth 1 -type f \( -iname \*.mp4 -o -iname \*.mkv \) | xargs -0n1 | head -n1)"
    [[ -z "$vid_test" ]] && exit 0

    # Stores the current video width, aspect ratio, profile, bit rate, and total duration in variables for use later in the ffmpeg command line
    aspect_ratio=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 -pretty "$vid" 2>/dev/null)
    file_length=$(ffprobe -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$vid" 2>/dev/null)
    max_rate=$(ffprobe -hide_banner -show_entries format=bit_rate -of default=nk=1:nw=1 -pretty "$vid" 2>/dev/null)
    file_height=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 -pretty "$vid" 2>/dev/null)
    file_width=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 -pretty "$vid" 2>/dev/null)

    # Modify vars to get file input and output names
    file_in="$vid"
    fext="${file_in#*.}"
    file_out="$random_dir/${file_in%.*} (x265).$fext"

    # Trim the strings
    trim=${max_rate::-11}

    # Gets the input videos max datarate and applies logic to determine bitrate, bufsize, and maxrate variables
    trim=$(bc <<< "scale=2 ; $trim * 1000")
    br=$(bc <<< "scale=2 ; $trim / 2")
    bitrate="${br::-3}"
    maxrate=$(( bitrate * 2 ))
    bs=$(bc <<< "scale=2 ; $br * 2")
    bufsize="${bs::-3}"
    length=$(( ${file_length::-7} / 60 ))

    # Print the video stats in the terminal
    clear
    cat <<EOF
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

Working Dir:     $PWD

Input File:      $file_in
Output File:     $file_out

Aspect Ratio:    $aspect_ratio
Dimensions:      ${file_width}x$file_height

Maxrate:         ${maxrate}k
Bufsize:         ${bufsize}k
Bitrate:         ${bitrate}k

Length:          ${length} mins

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF

    # Execute ffpb
    echo
    if ffpb -y \
            -vsync 0 \
            -hide_banner \
            -hwaccel_output_format cuda \
            -threads $(nproc --all) \
            -i "$file_in" \
            -threads $(nproc --all) \
            -c:v hevc_nvenc \
            -preset medium \
            -profile main10 \
            -pix_fmt p010le \
            -rc:v vbr \
            -tune hq \
            -b:v "${bitrate}k" \
            -bufsize "${bitrate}k" \
            -maxrate "${maxrate}k" \
            -bf:v 3 \
            -g 250 \
            -b_ref_mode middle \
            -qmin 0 \
            -temporal-aq 1 \
            -rc-lookahead 20 \
            -i_qfactor 0.75 \
            -b_qfactor 1.1 \
            -c:a copy \
            "$file_out"; then
        log "Video conversion completed."
        google_speech "Video conversion completed." 2>/dev/null
        mv "$file_out" "$PWD/${file_in%.*} (x265).$fext"
    else
        sudo rm -fr "$random_dir"
        google_speech "Video conversion failed for $file_in." 2>/dev/null
        fail "Video conversion failed for $file_in."
    fi
    clear
done

# Remove the temporary directory
sudo rm -fr "$random_dir"
