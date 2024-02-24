#!/usr/bin/env bash
# shellcheck disable=SC2066,SC2068,SC2086,SC2162

# SET THE PATH VARIABLE
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$PATH:$HOME/.local/bin"
fi

# INSTALLL THE REQUIRED APT PACKAGES
pkgs=(
    ffmpegthumbnailer ffmpegthumbs libffmpegthumbnailer4v5
    libsox-dev python3-pip sox trash-cli
)

for pkg in ${pkgs[@]}
do
    missing_pkg=$(sudo dpkg -l | grep -o "$pkg")
    if [ -z "$missing_pkg" ]; then
        missing_pkgs+=" $pkg"
    fi
done

if [ -n "$missing_pkgs" ]; then
    printf "%s\n\n" "$ Installing: $missing_pkgs"
    if ! sudo apt -y install $missing_pkgs; then
        fail_fn "Failed to install the required APT packages: $missing_pkgs"
    else
        sudo apt -y install bc
        printf "\n%s\n\n" "The required APT packages were successfully installed!"
    fi
fi
clear

# Install the required pip packages
# Specify a permanent location for the virtual environment
venv_dir="$HOME/my_venv"

# Check if the virtual environment already exists
if [ ! -d "$venv_dir" ]; then
    echo "Creating a virtual environment in $venv_dir"
    python3 -m venv "$venv_dir"
else
    echo "Using existing virtual environment in $venv_dir"
fi

# Activate the virtual environment
source "$venv_dir/bin/activate"

# Function to check if a package is installed
is_package_installed() {
    pip list | grep "^$1 " > /dev/null
}

# List of required packages
required_packages=(ffpb google_speech)

# Iterate over the required packages and install if not already installed
for pkg in "${required_packages[@]}"; do
    if is_package_installed "$pkg"; then
        echo "$pkg is already installed."
    else
        echo "Installing $pkg..."
        pip install "$pkg" > /dev/null && echo "$pkg installed successfully." || { echo "Failed to install $pkg."; exit 1; }
    fi
done

echo "Setup complete. The python virtual environment is ready to use."


# CREATE AN OUTPUT FILE THAT CONTAINS ALL OF THE VIDEO PATHS AND USE IT TO LOOP THE CONTENTS
tmp_list_dir="$(mktemp -d)"
cat > "$tmp_list_dir/list.txt" <<'EOF'
/path/to/video.mkv
/path/to/video.mp4
EOF

while read -u 9 video
do
    # STORES THE CURRENT VIDEO WIDTH, ASPECT RATIO, PROFILE, BIT RATE, AND TOTAL DURATION IN VARIABLES FOR USE LATER IN THE FFMPEG COMMAND LINE
    aspect_ratio=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 -pretty "$video" 2>/dev/null)
    length=$(ffprobe -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video" 2>/dev/null)
    maxrate=$(ffprobe -hide_banner -show_entries format=bit_rate -of default=nk=1:nw=1 -pretty "$video" 2>/dev/null)
    height=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 -pretty "$video" 2>/dev/null)
    width=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 -pretty "$video" 2>/dev/null)

    # MODIFY VARS TO GET FILE INPUT AND OUTPUT NAMES
    file_in="$video"
    fext="${video#*.}"
    file_out="${video%.*} (x265).$fext"

    # GETS THE INPUT VIDEOS MAX DATARATE AND APPLIES LOGIC TO DETERMINE bitrate, bufsize, AND MAXRATE VARIABLES
    trim=$(bc <<< "scale=2 ; ${maxrate::-11} * 1000")
    btr=$(bc <<< "scale=2 ; $trim / 2")
    bitrate="${btr::-3}"
    maxrate=$((bitrate * 3))
    bfs=$(bc <<< "scale=2 ; $btr * 2")
    bufsize="${bfs::-3}"
    length=$((${length::-7} / 60))

    # PRINT THE VIDEO STATS IN THE TERMINAL
    cat <<EOF
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

Working Dir:     $PWD

Input File:      $file_in
Output File:     $file_out

Aspect Ratio:    $aspect_ratio
Dimensions:      ${width}x${height}

Maxrate:         ${maxrate}k
Bufsize:         ${bufsize}k
Bitrate:         ${bitrate}k

Length:          $length mins

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF

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
            sudo rm "$file_in"
        fi
    else
        google_speech "Video conversion failed." 2>/dev/null
        echo
        exit 1
    fi
    clear
done 9< "$tmp_list_dir/list.txt"
