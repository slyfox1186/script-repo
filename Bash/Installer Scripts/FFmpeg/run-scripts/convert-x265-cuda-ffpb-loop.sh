#!/usr/bin/env bash
# Shellcheck disable=sc2066,sc2068,sc2086,sc2162

# Set the path variable
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$PATH:$HOME/.local/bin"
fi

# Create the output directories
if [ ! -d completed ] || [ ! -d original ]; then
    mkdir completed original
fi

# Installl the required apt packages
pkgs=(
    bc ffmpegthumbnailer ffmpegthumbs libffmpegthumbnailer4v5
    libsox-dev python3-pip sox trash-cli
)

missing_pkgs=""
for pkg in ${pkgs[@]}
do
    missing_pkg="$(sudo dpkg -l | grep -o "$pkg")"
    if [ -z "${missing_pkg}" ]; then
        missing_pkgs+=" $pkg"
    fi
done

if [ -n "$missing_pkgs" ]; then
    printf "%s\n\n" "$ Installing: $missing_pkgs"
    if ! sudo apt -y install $missing_pkgs; then
        fail_fn "Failed to install the required APT packages: $missing_pkgs"
    else
        printf "\n%s\n\n" "The required APT packages were successfully installed!"
    fi
else
    printf "%s\n\n" "The required APT packages are already installed."
fi

# Install the required pip packages
pip_dir="$(mktemp -d)"
echo "ffpb" > "$pip_dir"/requirements.txt
echo "google_speech" >> "$pip_dir"/requirements.txt
if ! pip install --user -r "$pip_dir"/requirements.txt &>/dev/null; then
    printf "%s\n\n" "Failed to install the pip packages."
    exit 1
fi
sudo rm -fr "$pip_dir"

# Delete any files from previous runs
del_this="$(du -ah --max-depth=1 | grep -Eo "[\/].*\(x265\)\.m(p4|kv)$" | grep -Eo "[A-Za-z0-9].*\(x265\)\.m(p4|kv)$")"

if [ -n "$del_this" ]; then
    printf "%s\n\n%s\n%s\n%s\n\n" \
        "Do you want to delete this video before continuing?: $del_this" \
        "[1] Yes" \
        "[2] No" \
        "[3] Exit"
    read -p "Your choices are (1 to 3): " choice

    case "$choice" in
        1)      rm "$del_this"; clear;;
        2)      clear;;
        3)      exit 0;;
        *)
                clear
                printf "%s\n\n" "Bad user input."
                exit 1
                ;;
    esac
fi

# Make sure there are videos available to convert
vid_test="$(find ./ -maxdepth 1 -type f \( -iname \*.mp4 -o -iname \*.mkv \) | xargs -0n1 | head -n1)"

if [ -z "$vid_test" ]; then
    google_speech "No videos were located. Please add some to the script"\""s directory and try again." 2>/dev/null
    clear
    exit 0
fi

# Create a temporary output folder in the /tmp directory
ff_dir="$(mktemp -d)"

for vid in *.{mp4,mkv}
do
    vid_test="$(find ./ -maxdepth 1 -type f \( -iname \*.mp4 -o -iname \*.mkv \) | xargs -0n1 | head -n1)"
    if [ -z "$vid_test" ]; then
        exit 0
    fi

# Stores the current video width, aspect ratio, profile, bit rate, and total duration in variables for use later in the ffmpeg command line
    aspect_ratio="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 -pretty "$vid" 2>/dev/null)"
    file_length="$(ffprobe -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$vid" 2>/dev/null)"
    max_rate="$(ffprobe -hide_banner -show_entries format=bit_rate -of default=nk=1:nw=1 -pretty "$vid" 2>/dev/null)"
    file_height="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 -pretty "$vid" 2>/dev/null)"
    file_width="$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 -pretty "$vid" 2>/dev/null)"

# Modify vars to get file input and output names
    file_in="$vid"
    fext="${file_in#*.}"
    file_out="$ff_dir/${file_in%.*} (x265).${fext}"

# Trim the strings
    trim="${max_rate::-11}"

# Gets the input videos max datarate and applies logic to determine bitrate, bufsize, and maxrate variables
    trim="$(bc <<< "scale=2 ; $trim * 1000")"
    br="$(bc <<< "scale=2 ; $trim / 2")"
    bitrate="${br::-3}"
    maxrate="$(( bitrate * 2 ))"
    bs="$(bc <<< "scale=2 ; $br * 2")"
    bufsize="${bs::-3}"
    length="$(( ${file_length::-7} / 60 ))"

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
            -i "$file_in" \
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
        google_speech "Video conversion completed." 2>/dev/null
        if [ -f "$file_out" ]; then
            mv "$file_in" "$PWD"/original
            mv "$file_out" "$PWD"/completed
        fi
    else
        google_speech "Video conversion failed." 2>/dev/null
        echo
        read -p "Press enter to exit."
        sudo rm -fr "$ff_dir"
        exit 1
    fi
    clear
done

# Remove the temporary directory
sudo rm -fr "$ff_dir"
