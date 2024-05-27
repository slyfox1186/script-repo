#!/usr/bin/env bash

# Default paths file
log_file="conversion.log"

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "Usage: $0 [-p paths_file] [-l log_file]"
    echo "  -l log_file     Log file to save output (default: conversion.log)"
}

# Parse command-line arguments
while getopts "p:l:h" opt; do
    case "$opt" in
        l ) log_file="$OPTARG" ;;
        h ) show_usage; exit 0 ;;
        * ) show_usage; exit 1 ;;
    esac
done

# Create a temporary file to store the video paths
temp_file=$(mktemp)
error_log=$(mktemp /tmp/error_log.XXXXXX)

# Add the video paths that FFmpeg will process to the temporary file
cat > "$temp_file" <<'EOF'
/path/to/video.mkv
/path/to/video.mp4
EOF

# Log functions
log() {
    local message
    message="$1"
    echo -e "\n${GREEN}[INFO]${NC} $message\n" | tee -a "$log_file"
}

fail() {
    local message
    message="$1"
    echo -e "\n${RED}[ERROR]${NC} $message\n" | tee -a "$log_file"
    echo "$message" >> "$error_log"
    exit 1
}

# Cleanup function to remove temporary files
cleanup() {
    rm -f "$temp_file" "$error_log"
}

# Check for required dependencies before proceeding
check_dependencies() {
    local -a missing_pkgs
    local pkg

    missing_pkgs=()
    for pkg in bc ffpb google_speech sed ffmpeg notify-send; do
        if ! command -v "$pkg" &>/dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done
    if [[ ${#missing_pkgs[@]} -ne 0 ]]; then
        fail "Missing dependencies: ${missing_pkgs[*]}. Please install them."
    fi
}

# Function to remove a video path from the script itself
remove_video_path_from_script() {
    local video_path script_path
    video_path="$1"
    script_path="$0"
    
    sed -i "\|$video_path|d" "$script_path"
}

# Function to execute ffmpeg command
convert_with_ffmpeg() {
    local audio_codec bitrate bufsize file_out maxrate threads video
    video="$1"
    audio_codec="$2"
    file_out="$3"
    bitrate="$4"
    bufsize="$5"
    maxrate="$6"
    threads="$7"

    ffpb -y -hide_banner -hwaccel_output_format cuda \
        -threads "$threads" -i "$video" -fps_mode:v vfr \
        -c:v hevc_nvenc -preset medium -profile:v main10 \
        -pix_fmt p010le -rc:v vbr -tune:v hq -b:v "${bitrate}k" \
        -bufsize:v "${bufsize}k" -maxrate:v "${maxrate}k" -bf:v 3 \
        -g:v 250 -b_ref_mode:v middle -qmin:v 0 -temporal-aq:v 1 \
        -rc-lookahead:v 20 -i_qfactor:v 0.75 -b_qfactor:v 1.1 -c:a "$audio_codec" "$file_out"
}

# Main video conversion function
convert_videos() {
    local aspect_ratio bitrate bufsize file_out height length maxrate original_bitrate
    local threads total_input_size total_output_size total_space_saved width
    local video input_size_bytes input_file output_file input_size_mb output_size space_saved
    local video_name count total_videos progress estimated_output_size estimated_bitrate

    total_input_size=0
    total_output_size=0
    total_space_saved=0
    count=0
    total_videos=$(wc -l < "$temp_file")

    while read -r -u 9 video; do
        if [[ ! -f "$video" ]]; then
            log "File not found: $video. Removing from list."
            remove_video_path_from_script "$video"
            continue
        fi

        count=$((count + 1))
        progress=$((count * 100 / total_videos))
        
        aspect_ratio=$(ffprobe -v error -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 "$video")
        height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$video")
        input_size_bytes=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "$video")
        length=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video")
        original_bitrate=$(ffprobe -v error -show_entries format=bit_rate -of default=nk=1:nw=1 "$video" | awk '{print int($1/1024)}')
        width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$video")

        file_out="${video%.*} (x265).${video##*.}"

        # Calculate optimal settings for x265
        bitrate=$(echo "$original_bitrate * 0.5" | bc) # Aim for about 50% of the original bitrate
        bufsize=$(echo "$bitrate * 1.5" | bc) # Set bufsize to 150% of the new bitrate
        maxrate=$(echo "$bitrate * 2" | bc) # Allow maxrate to peak to 200% of the bitrate

        # Convert floating point to integer
        bitrate=$(printf "%.0f" "$bitrate")
        bufsize=$(printf "%.0f" "$bufsize")
        maxrate=$(printf "%.0f" "$maxrate")

        # Ensure integer arithmetic by truncating to integers before any operations
        length=$(printf "%.0f" "$length")
        length=$((length / 60))

        # Determine the number of threads based on the CPU cores available
        threads=$(nproc --all)
        threads=$((threads>16 ? 16 : threads)) # Cap at 16 threads for efficiency

        # Extract the file name from the full path using variable substitution
        input_file="${video##*/}"
        output_file="${file_out##*/}"
        input_size_mb=$(echo "scale=2; $input_size_bytes / 1024 / 1024" | bc)
        
        # Estimate output size and bitrate
        estimated_bitrate=$bitrate  # Bitrate is halved for output estimation
        estimated_output_size=$(echo "scale=2; ($estimated_bitrate * $length * 60) / 8 / 1024" | bc)

        # Print video stats in the terminal
        printf "\n${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}\n\n"
        printf "${YELLOW}Progress:${NC} ${PURPLE}%d%%${NC}\n" "$progress"
        printf "${YELLOW}Working Directory:${NC}  ${PURPLE}%s${NC}\n\n" "$PWD"
        printf "${YELLOW}Input File:${NC}         ${CYAN}%s${NC}\n\n" "$input_file"
        printf "${YELLOW}Size:${NC}               ${PURPLE}%.2f MB${NC}\n" "$input_size_mb"
        printf "${YELLOW}Bitrate:${NC}            ${PURPLE}%s kbps${NC}\n" "$original_bitrate"
        printf "${YELLOW}Aspect Ratio:${NC}       ${PURPLE}%s${NC}\n" "$aspect_ratio"
        printf "${YELLOW}Resolution:${NC}         ${PURPLE}%sx%s${NC}\n" "$width" "$height"
        printf "${YELLOW}Duration:${NC}           ${PURPLE}%s mins${NC}\n" "$length"
        printf "\n${YELLOW}Output File:${NC}        ${CYAN}%s${NC}\n" "$output_file"
        printf "${YELLOW}Estimated Output Bitrate:${NC}  ${PURPLE}%s kbps${NC}\n" "$estimated_bitrate"
        printf "${YELLOW}Estimated Output Size:${NC}  ${PURPLE}%.2f MB${NC}\n" "$estimated_output_size"
        printf "\n${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}\n"

        log "Converting $video"

        input_size=$(du -m "$video" | cut -f1)
        total_input_size=$((total_input_size + input_size))

        # Attempt to copy audio codec first, fallback to re-encoding if it fails
        if ! convert_with_ffmpeg "$video" "copy" "$file_out" "$bitrate" "$bufsize" "$maxrate" "$threads"; then
            # If the above command fails, re-encode the audio to AAC
            if ! convert_with_ffmpeg "$video" "aac" "$file_out" "$bitrate" "$bufsize" "$maxrate" "$threads"; then
                google_speech "Video conversion failed." &>/dev/null
                fail "Video conversion failed for: $video"
            fi
        fi

        google_speech "Video converted." &>/dev/null

        log "Video conversion completed: $file_out"

        output_size=$(du -m "$file_out" | cut -f1)
        total_output_size=$((total_output_size + output_size))
        space_saved=$((input_size - output_size))
        total_space_saved=$((total_space_saved + space_saved))

        # Extract the video name from the full path using variable expansion
        video_name="${video##*/}"

        echo -e "${YELLOW}Total space savings for \"$video_name\": ${PURPLE}$space_saved MB${NC}"
        echo -e "${YELLOW}Total cumulative space saved: ${PURPLE}$total_space_saved MB${NC}"

        rm -f "$video"

        # Remove the video path from the script itself using awk
        remove_video_path_from_script "$video"
    done 9< "$temp_file"

    log "Total input size: ${total_input_size} MB"
    log "Total output size: ${total_output_size} MB"
    log "Total space saved: ${total_space_saved} MB"
}

# Register the cleanup function to be called on the EXIT signal
trap cleanup EXIT

# Check dependencies and start the video conversion process
check_dependencies
convert_videos
notify-send "Video conversion process completed."
