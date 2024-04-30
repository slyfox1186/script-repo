#!/usr/bin/env bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log functions
log() {
    echo -e "\\n${GREEN}[INFO] $1${NC}\\n"
}

fail() {
    echo -e "\\n${RED}[ERROR] $1${NC}\\n"
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
        echo -e "${RED}Missing dependencies: ${missing_dependencies[*]}. Please install them.${NC}"
        exit 1
    fi
}

# Main video conversion function
convert_videos() {
    local aspect_ratio bitrate bufsize file_out height length maxrate temp_file threads trim width
    temp_file=$(mktemp)

    # Create an output file that contains all of the video paths
    cat > "$temp_file" <<'EOF'
/path/to/video.mkv
/path/to/video.mp4
EOF

    while read -u 9 video; do
        local aspect_ratio bufsize file_out height length maxrate threads trim width bitrate

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
        bufsize=$((bitrate * 2))
        length=$(printf "%.0f" "$length")
        length=$((length / 60))

        # Determine the number of threads based on the result of '$(nproc --all)'
        if [ "$(nproc --all)" -ge 16 ]; then
            threads=16
        else
            threads=$(nproc --all)
        fi

        # Print video stats in the terminal
        cat <<EOF
${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}
${YELLOW}Working Dir:${NC}     ${PURPLE}$(pwd)${NC}
${YELLOW}Input File:${NC}      ${CYAN}$video${NC}
${YELLOW}Output File:${NC}     ${CYAN}$file_out${NC}
${YELLOW}Aspect Ratio:${NC}    ${PURPLE}$aspect_ratio${NC}
${YELLOW}Dimensions:${NC}      ${PURPLE}${width}x${height}${NC}
${YELLOW}Maxrate:${NC}         ${PURPLE}${maxrate}k${NC}
${YELLOW}Bufsize:${NC}         ${PURPLE}${bufsize}k${NC}
${YELLOW}Bitrate:${NC}         ${PURPLE}${bitrate}k${NC}
${YELLOW}Length:${NC}          ${PURPLE}$length mins${NC}
${YELLOW}Threads:${NC}         ${PURPLE}$threads${NC}
${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}
EOF

        log "Converting $video"

        if ffpb -y -hide_banner -hwaccel_output_format cuda \
            -threads "$threads" -i "$video" -fps_mode vfr \
            -threads "$threads" -c:v hevc_nvenc -preset medium \
            -profile:v main10 -pix_fmt p010le -rc:v vbr -tune hq \
            -b:v "${bitrate}k" -bufsize "${bufsize}k" -maxrate "${maxrate}k" \
            -bf:v 3 -g 250 -b_ref_mode middle -qmin 0 -temporal-aq 1 \
            -rc-lookahead 20 -i_qfactor 0.75 -b_qfactor 1.1 -c:a copy "$file_out"; then
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
