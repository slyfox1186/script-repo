#!/usr/bin/env bash
# shellcheck disable=SC2066,SC2068,SC2086,SC2162

# Set the path variable
[[ -d "$HOME/.local/bin" ]] && export PATH="$PATH:$HOME/.local/bin"

# Create an output file that contains all of the video paths and use it to loop the contents
temp_file=$(mktemp)
cat > "$temp_file" <<'EOF'
/path/to/video.mp4
/path/to/video.mkv
EOF

while read -u 9 video; do
    # Stores the current video width, aspect ratio, profile, bit rate, and total duration in variables for use later in the ffmpeg command line
    aspect_ratio=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 -pretty "$video" 2>/dev/null)
    length=$(ffprobe -hide_banner -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video" 2>/dev/null)
    maxrate=$(ffprobe -hide_banner -show_entries format=bit_rate -of default=nk=1:nw=1 -pretty "$video" 2>/dev/null)
    height=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 -pretty "$video" 2>/dev/null)
    width=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 -pretty "$video" 2>/dev/null)

    # Modify vars to get file input and output names
    file_in="$video"
    fext="${video#*.}"
    file_out="${video%.*} (x265).$fext"

    # Gets the input videos max datarate and applies logic to determine bitrate, bufsize, and maxrate variables
    trim=$(bc <<< "scale=2 ; ${maxrate::-11} * 1000")
    btr=$(bc <<< "scale=2 ; $trim / 2")
    bitrate="${btr::-3}"
    maxrate=$((bitrate * 3))
    bfs=$(bc <<< "scale=2 ; $btr * 2")
    bufsize="${bfs::-3}"
    length=$((${length::-7} / 60))

    # Print the video stats in the terminal
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
        [[ -f "$file_out" ]] && sudo rm "$file_in"

        # Remove the successfully encoded video's file path from the temporary file
        sed -i "\|^$video\$|d" "$temp_file"
    else
        google_speech "Video conversion failed." 2>/dev/null
        exit 1
    fi
    clear
done 9< "$temp_file"
