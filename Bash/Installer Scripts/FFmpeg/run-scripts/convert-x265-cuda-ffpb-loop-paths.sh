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
    echo -e "\\n${GREEN}[INFO]${NC} $1 $2\\n"
}

fail() {
    echo -e "\\n${RED}[ERROR]${NC} $1 $2\\n"
    exit 1
}

# Check for required dependencies before proceeding
check_dependencies() {
    local missing_pkgs
    missing_pkgs=()
    for pkg in bc ffpb google_speech sed; do
        if ! command -v "$pkg" &>/dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done
    if [ ${#missing_pkgs[@]} -ne 0 ]; then
        fail "Missing dependencies: ${missing_pkgs[*]}. Please install them."
    fi
}

# Main video conversion function
convert_videos() {
    local aspect_ratio bitrate bufsize file_out height length maxrate original_bitrate
    local temp_file threads total_input_size total_output_size total_space_saved width
    temp_file=$(mktemp)

    # Create an output file that contains all of the video paths
    cat > "$temp_file" <<'EOF'
/path/to/video.mkv
/path/to/video.mp4
EOF

    total_input_size=0
    total_output_size=0
    total_space_saved=0

    while read -u 9 video; do
        aspect_ratio=$(ffprobe -v error -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 "$video")
        height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$video")
        width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$video")
        length=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video")
        original_bitrate=$(ffprobe -v error -show_entries format=bit_rate -of default=nk=1:nw=1 "$video")

        file_out="${video%.*} (x265).${video##*.}"

        # Calculate optimal settings for x265
        bitrate=$(echo "$original_bitrate * 0.5" | bc) # Aim for about 50% of the original bitrate
        bufsize=$(echo "$bitrate * 1.5" | bc) # Set bufsize to 150% of the new bitrate
        maxrate=$(echo "$bitrate * 2" | bc) # Allow maxrate to peak to 200% of the bitrate

        # Convert floating point to integer
        bitrate=$(printf "%.0f" "$bitrate")
        bufsize=$(printf "%.0f" "$bufsize")
        maxrate=$(printf "%.0f" "$maxrate")

        bitrate=$((bitrate / 1024))
        bufsize=$((bufsize / 1024))
        maxrate=$((maxrate / 1024))

        # Ensure integer arithmetic by truncating to integers before any operations
        length=$(printf "%.0f" "$length")
        length=$((length / 60))

        # Determine the number of threads based on the CPU cores available
        threads=$(nproc --all)
        threads=$((threads>16 ? 16 : threads)) # Cap at 16 threads for efficiency

        # Print video stats in the terminal
        printf "\\n${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}\\n"
        printf "${YELLOW}Working Dir:${NC}     ${PURPLE}%s${NC}\\n" "$PWD"
        printf "${YELLOW}Input File:${NC}      ${CYAN}%s${NC}\\n" "$video"
        printf "${YELLOW}Output File:${NC}     ${CYAN}%s${NC}\\n" "$file_out"
        printf "${YELLOW}Aspect Ratio:${NC}    ${PURPLE}%s${NC}\\n" "$aspect_ratio"
        printf "${YELLOW}Dimensions:${NC}      ${PURPLE}%sx%s${NC}\\n" "$width" "$height"
        printf "${YELLOW}Maxrate:${NC}         ${PURPLE}%sk${NC}\\n" "$maxrate"
        printf "${YELLOW}Bufsize:${NC}         ${PURPLE}%sk${NC}\\n" "$bufsize"
        printf "${YELLOW}Bitrate:${NC}         ${PURPLE}%sk${NC}\\n" "$bitrate"
        printf "${YELLOW}Length:${NC}          ${PURPLE}%s mins${NC}\\n" "$length"
        printf "${YELLOW}Threads:${NC}         ${PURPLE}%s${NC}\\n" "$threads"
        printf "${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}\\n"

        log "Converting${NC}" "$video"

        input_size=$(du -m "$video" | cut -f1)
        total_input_size=$((total_input_size + input_size))

        # Conversion using ffmpeg with HEVC codec
        if ffpb -y -hide_banner -hwaccel_output_format cuda \
            -threads "$threads" -i "$video" -fps_mode:v vfr \
            -c:v hevc_nvenc -preset medium \
            -profile:v main10 -pix_fmt p010le -rc:v vbr -tune:v hq \
            -b:v "${bitrate}k" -bufsize:v "${bufsize}k" -maxrate:v "${maxrate}k" \
            -bf:v 3 -g:v 250 -b_ref_mode:v middle -qmin:v 0 -temporal-aq:v 1 \
            -rc-lookahead:v 20 -i_qfactor:v 0.75 -b_qfactor:v 1.1 -c:a copy "$file_out"; then

            google_speech "Video converted." &>/dev/null

            log "Video conversion completed:${NC}" "$file_out"

            output_size=$(du -m "$file_out" | cut -f1)
            total_output_size=$((total_output_size + output_size))
            space_saved=$((input_size - output_size))
            total_space_saved=$((total_space_saved + space_saved))

            echo -e "${YELLOW}Space saved for \"$video##*/\": ${PURPLE}$space_saved MB${NC}"
            echo -e "${YELLOW}Total cumulative space saved: ${PURPLE}$total_space_saved MB${NC}"

            rm "$video"

            sed -i "\|^$video\$|d" "$temp_file"
        else
            google_speech "Video conversion failed." &>/dev/null
            fail "Video conversion failed for: $video"
        fi
    done 9< "$temp_file"
    rm "$temp_file"

    log "Total input size: ${total_input_size} MB"
    log "Total output size: ${total_output_size} MB"
    log "Total space saved: ${total_space_saved} MB"
}

# Check dependencies and start the video conversion process
check_dependencies
convert_videos
