#!/usr/bin/env bash

# Log functions
log() {
    echo "[INFO] $1"
}

fail() {
    echo "[ERROR] $1"
    exit 1
}

# Check for required dependencies before proceeding
check_dependencies() {
    local missing_dependencies=()
    for dependency in ffpb bc sed; do
        if ! command -v "$dependency" &>/dev/null; then
            missing_dependencies+=("$dependency")
        fi
    done
    if [ ${#missing_dependencies[@]} -ne 0 ]; then
        echo "Missing dependencies: ${missing_dependencies[*]}. Please install them."
        exit 1
    fi
}

# Main video conversion function
convert_videos() {
    local temp_file=$(mktemp)

    # Create an output file that contains all of the video paths
    cat > "$temp_file" <<'EOF'
/path/to/video.mkv
/path/to/video.mp4
EOF

    while read -u 9 video; do
        local aspect_ratio file_out height length maxrate width trim bitrate
        aspect_ratio=$(ffprobe -v error -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 "$video")
        length=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video")
        maxrate=$(ffprobe -v error -show_entries format=bit_rate -of default=nk=1:nw=1 "$video")
        height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$video")
        width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$video")

        file_out="${video%.*} (x265).${video##*.}"

        # Using bc for floating-point arithmetic
        trim=$(echo "scale=2; $maxrate / 1000" | bc)
        bitrate=$(echo "scale=2; $trim / 2" | bc)
        # Converting bitrate to integer for compatibility with ffmpeg options
        bitrate=$(printf "%.0f" "$bitrate")
        maxrate=$((bitrate * 3))
        local bufsize=$((bitrate * 2))
        length=$(printf "%.0f" "$length")
        length=$((length / 60))

        # Print video stats in the terminal
        cat <<EOF

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

Working Dir:     $(pwd)

Input File:      $video
Output File:     $file_out

Aspect Ratio:    $aspect_ratio
Dimensions:      ${width}x${height}

Maxrate:         ${maxrate}k
Bufsize:         ${bufsize}k
Bitrate:         ${bitrate}k

Length:          $length mins

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

EOF

        log "Converting $video"
        
        if ffpb -y -hide_banner -hwaccel_output_format cuda \
                -threads $(nproc --all) -i "$video" -fps_mode vfr -threads $(nproc --all) -c:v hevc_nvenc -preset medium -profile:v main10 \
                -pix_fmt p010le -rc:v vbr -tune hq -b:v "${bitrate}k" \
                -bufsize "${bufsize}k" -maxrate "${maxrate}k" -bf:v 3 -g 250 \
                -b_ref_mode middle -qmin 0 -temporal-aq 1 -rc-lookahead 20 \
                -i_qfactor 0.75 -b_qfactor 1.1 -c:a copy "$file_out"; then
            log "Video conversion completed: $file_out"
            rm "$video"
            sed -i "\|^$video\$|d" "$temp_file"
        else
            fail "Video conversion failed for: $video"
        fi
    done 9< "$temp_file"
    rm "$temp_file"
}

# Check dependencies and start the video conversion process
check_dependencies
convert_videos
