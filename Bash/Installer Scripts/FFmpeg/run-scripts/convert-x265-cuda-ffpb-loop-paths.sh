#!/usr/bin/env bash

# Create a temporary file to store the video paths in
temp_file=$(mktemp)

# Add the video paths that FFmpeg will process to the temporary file that was created above
cat > "$temp_file" <<'EOF'
/path/to/video1.mp4
/path/to/video2.mp4
EOF

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
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
    for pkg in bc ffmpeg google_speech awk; do
        if ! command -v "$pkg" &>/dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done
    if [ ${#missing_pkgs[@]} -ne 0 ]; then
        fail "Missing dependencies: ${missing_pkgs[*]}. Please install them."
    fi
}

# Function to remove a video path from the heredoc
remove_video_path() {
    local video_path
    video_path="$1"
    
    # Remove the video path from the heredoc using awk
    awk -v path="$video_path" '!index($0, path)' "$0" > "$0.tmp" && mv "$0.tmp" "$0"
}

# Function to run ffmpeg command
run_ffmpeg() {
    local video audio_codec file_out bitrate bufsize maxrate threads
    video="$1"
    audio_codec="$2"
    file_out="$3"
    bitrate="$4"
    bufsize="$5"
    maxrate="$6"
    threads="$7"

    ffmpeg -y -hide_banner -hwaccel_output_format cuda \
        -threads "$threads" -i "$video" -fps_mode:v vfr \
        -c:v hevc_nvenc -preset medium -profile:v main10 \
        -pix_fmt p010le -rc:v vbr -tune:v hq -b:v "${bitrate}k" \
        -bufsize:v "${bufsize}k" -maxrate:v "${maxrate}k" -bf:v 3 \
        -g:v 250 -b_ref_mode:v middle -qmin:v 0 -temporal-aq:v 1 \
        -rc-lookahead:v 20 -i_qfactor:v 0.75 -b_qfactor:v 1.1 \
        -c:a "$audio_codec" "$file_out"
}

# Function to handle successful conversion
handle_success() {
    local video file_out input_size output_size total_input_size total_output_size total_space_saved

    video="$1"
    file_out="$2"
    input_size="$3"
    total_input_size="$4"
    total_output_size="$5"
    total_space_saved="$6"

    google_speech "Video converted." &>/dev/null

    log "Video conversion completed:${NC}" "$file_out"

    output_size=$(du -m "$file_out" | cut -f1)
    total_output_size=$((total_output_size + output_size))
    space_saved=$((input_size - output_size))
    total_space_saved=$((total_space_saved + space_saved))

    # Extract the video name from the full path using variable expansion
    video_name="${video##*/}"

    echo -e "${YELLOW}Total space savings for \"$video_name\": ${MAGENTA}$space_saved MB${NC}"
    echo -e "${YELLOW}Total cumulative space saved: ${MAGENTA}$total_space_saved MB${NC}"

    rm -f "$video"

    # Remove the video path from the script itself using awk
    remove_video_path "$video"
}

# Main video conversion function
convert_videos() {
    local aspect_ratio bitrate bufsize file_out height length maxrate original_bitrate
    local threads total_input_size total_output_size total_space_saved width
    local progress total_videos

    total_input_size=0
    total_output_size=0
    total_space_saved=0
    total_videos=$(wc -l < "$temp_file")
    count=0

    while read -r -u 9 video; do
        if [[ ! -f "$video" ]]; then
            log "File not found: $video. Removing from list."
            remove_video_path "$video"
            continue
        fi
        
        count=$((count + 1))
        progress=$((count * 100 / total_videos))

        aspect_ratio=$(ffprobe -v error -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 "$video")
        height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$video")
        input_size_bytes=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "$video")
        length=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video")
        original_bitrate=$(ffprobe -v error -show_entries format=bit_rate -of default=nk=1:nw=1 "$video")
        width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$video")

        file_out="${video%.*} (x265).${video##*.}"

        # Create the output directory if it does not exist
        mkdir -p "$(dirname "$file_out")"

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

        # Extract the file name from the full path using variable substitution
        input_file="${video##*/}"
        output_file="${file_out##*/}"
        input_size_mb=$(echo "scale=2; $input_size_bytes / 1024 / 1024" | bc)

        # Extract the parent directory of the video using variable expansion
        parent_dir="${video%/*}"

        # Print video stats in the terminal
        printf "\n${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}\n\n"
        printf "${YELLOW}Progress:${NC} ${MAGENTA}%d%%${NC}\n\n" "$progress"
        printf "${YELLOW}Working Directory:${NC}         ${MAGENTA}%s${NC}\n\n" "$PWD"
        printf "${YELLOW}Video Path:${NC}                ${MAGENTA}%s${NC}\n" "$parent_dir"
        printf "${YELLOW}Input File:${NC}                ${CYAN}%s${NC}" "$input_file"
        printf "\n${YELLOW}Output File:${NC}               ${CYAN}%s${NC}\n\n" "$output_file"
        printf "${YELLOW}Size:${NC}                      ${MAGENTA}%.2f MB${NC}\n" "$input_size_mb"
        printf "${YELLOW}Bitrate:${NC}                   ${MAGENTA}%s kbps${NC}\n" "$original_bitrate"
        printf "${YELLOW}Aspect Ratio:${NC}              ${MAGENTA}%s${NC}\n" "$aspect_ratio"
        printf "${YELLOW}Resolution:${NC}                ${MAGENTA}%sx%s${NC}\n" "$width" "$height"
        printf "${YELLOW}Duration:${NC}                  ${MAGENTA}%s mins${NC}\n\n" "$length"
        printf "${YELLOW}Estimated Output Bitrate:${NC}  ${MAGENTA}%s kbps${NC}\n" "$bitrate"
        printf "${YELLOW}Estimated Output Size:${NC}     ${MAGENTA}%.2f MB${NC}\n" "$estimated_output_size"
        printf "\n${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}\n"

        log "Converting${NC}" "$video"

        input_size=$(du -m "$video" | cut -f1)
        total_input_size=$((total_input_size + input_size))

        # Conversion using ffmpeg with HEVC codec
        if run_ffmpeg "$video" "copy" "$file_out" "$bitrate" "$bufsize" "$maxrate" "$threads"; then
            handle_success "$video" "$file_out" "$input_size" "$total_input_size" "$total_output_size" "$total_space_saved"
        else
            # Fallback to AAC audio encoding if copying fails
            if run_ffmpeg "$video" "aac" "$file_out" "$bitrate" "$bufsize" "$maxrate" "$threads"; then
                handle_success "$video" "$file_out" "$input_size" "$total_input_size" "$total_output_size" "$total_space_saved"
            else
                google_speech "Video conversion failed." &>/dev/null
                fail "Video conversion failed for: $video"
            fi
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
