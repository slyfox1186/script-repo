#!/usr/bin/env bash

set -u

temp_file=$(mktemp)
trap 'rm -f "$temp_file"' EXIT

cat > "$temp_file" <<'EOF'
/path/to/video.mp4
/path/to/video.mkv
EOF

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

total_input_size=0
total_output_size=0
total_space_saved=0

log() {
    echo -e "\n${GREEN}[INFO]${NC} $*\n"
}

warn() {
    echo -e "\n${YELLOW}[WARNING]${NC} $*\n"
}

fail() {
    echo -e "\n${RED}[ERROR]${NC} $*\n"
    exit 1
}

kill_related_processes() {
    local pid cmd
    local -a all_pids=()

    while IFS= read -r pid; do
        [[ -n "$pid" && "$pid" != "$$" ]] && all_pids+=("$pid")
    done < <(pgrep -f 'ffpb|ffmpeg|google_speech' || true)

    if [[ ${#all_pids[@]} -eq 0 ]]; then
        log "No related processes found."
        return
    fi

    warn "Found ${#all_pids[@]} related process(es). Killing them..."
    for pid in "${all_pids[@]}"; do
        if ps -p "$pid" &>/dev/null; then
            cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            echo -e "${YELLOW}[WARNING]${NC} Killing process - $cmd with PID: $pid"
            sudo kill -9 "$pid"
        fi
    done
}

check_dependencies() {
    local cmd
    local -a missing=()

    for cmd in awk bc cut du ffpb ffprobe google_speech mktemp nproc pgrep ps sudo wc; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    [[ ${#missing[@]} -eq 0 ]] || fail "Missing dependencies: ${missing[*]}. Please install them."
}

remove_video_path() {
    local video_path
    video_path=$1
    awk -v path="$video_path" '$0 != path' "$0" > "$0.tmp" && mv "$0.tmp" "$0"
}

run_ffmpeg() {
    local video audio_codec file_out bitrate bufsize maxrate threads start_time
    video=$1
    audio_codec=$2
    file_out=$3
    bitrate=$4
    bufsize=$5
    maxrate=$6
    threads=$7
    start_time=$8

    ffpb \
        -y \
        -hide_banner \
        -hwaccel_output_format cuda \
        -threads "$threads" \
        -i "$video" \
        -ss "$start_time" \
        -fps_mode:v vfr \
        -c:v hevc_nvenc \
        -preset medium \
        -profile:v main10 \
        -pix_fmt p010le \
        -rc:v vbr \
        -tune:v hq \
        -b:v "${bitrate}k" \
        -bufsize:v "${bufsize}k" \
        -maxrate:v "${maxrate}k" \
        -bf:v 3 \
        -g:v 250 \
        -b_ref_mode:v middle \
        -qmin:v 0 \
        -temporal-aq:v 1 \
        -rc-lookahead:v 20 \
        -i_qfactor:v 0.75 \
        -b_qfactor:v 1.1 \
        -c:a "$audio_codec" \
        "$file_out"
}

print_video_stats() {
    local progress video file_out input_size_mb original_bitrate aspect_ratio
    local width height length_mins length_secs bitrate estimated_output_size
    local estimated_space_savings parent_dir output_file input_file

    progress=$1
    video=$2
    file_out=$3
    input_size_mb=$4
    original_bitrate=$5
    aspect_ratio=$6
    width=$7
    height=$8
    length_mins=$9
    length_secs=${10}
    bitrate=${11}
    estimated_output_size=${12}

    input_file=${video##*/}
    output_file=${file_out##*/}
    parent_dir=${video%/*}

    estimated_space_savings=$(echo "$input_size_mb - $estimated_output_size" | bc)

    printf "\n${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}\n\n"
    printf "${YELLOW}Progress:${NC} ${MAGENTA}%d%%${NC}\n\n" "$progress"
    printf "${YELLOW}Script Directory:${NC}           ${MAGENTA}%s${NC}\n\n" "$PWD"
    printf " ${YELLOW}Input File Path:${NC}           ${MAGENTA}%s${NC}\n\n" "$parent_dir"
    printf " ${YELLOW}Input Filename:${NC}            ${CYAN}%s${NC}\n" "$input_file"
    printf " ${YELLOW}Size:${NC}                      ${MAGENTA}%'0.2f MB${NC}\n" "$input_size_mb"
    printf " ${YELLOW}Bitrate:${NC}                   ${MAGENTA}%'d Kbps${NC}\n" "$((original_bitrate / 1000))"
    printf " ${YELLOW}Aspect Ratio:${NC}              ${MAGENTA}%s${NC}\n" "$aspect_ratio"
    printf " ${YELLOW}Resolution:${NC}                ${MAGENTA}%sx%s${NC}\n" "$width" "$height"
    printf " ${YELLOW}Duration:${NC}                  ${MAGENTA}%02d:%02d${NC}\n" "$length_mins" "$length_secs"
    printf " \n${YELLOW}Output Filename:${NC}           ${CYAN}%s${NC}\n" "$output_file"
    printf " ${YELLOW}Estimated Output Bitrate:${NC}  ${MAGENTA}%'d kbps${NC}\n" "$bitrate"
    printf " ${YELLOW}Estimated Output Size:${NC}     ${MAGENTA}%.2f MB${NC}\n" "$estimated_output_size"
    printf " ${YELLOW}Estimated Space Savings:${NC}   ${MAGENTA}%.2f MB${NC}\n" "$estimated_space_savings"
    printf "\n${BLUE}::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::${NC}\n"
}

handle_success() {
    local video file_out input_size output_size space_saved video_name
    video=$1
    file_out=$2
    input_size=$3
    video_name=${video##*/}

    google_speech "Video converted." &>/dev/null
    log "Video conversion completed: $file_out"

    output_size=$(du -m "$file_out" | cut -f1)
    space_saved=$((input_size - output_size))

    total_output_size=$((total_output_size + output_size))
    total_space_saved=$((total_space_saved + space_saved))

    echo -e "${YELLOW}Total space savings for \"$video_name\": ${MAGENTA}$space_saved MB${NC}"
    echo -e "${YELLOW}Total cumulative space saved: ${MAGENTA}$total_space_saved MB${NC}\n"
    echo -e "${YELLOW}Estimated Cumulative Space Savings: ${MAGENTA}$((total_input_size - total_output_size)) MB${NC}"

    rm -f "$video"
    remove_video_path "$video"
}

convert_single_video() {
    local progress video aspect_ratio height input_size input_size_bytes length
    local original_bitrate width start_time file_out bitrate bufsize maxrate
    local length_mins length_secs estimated_output_size input_size_mb threads

    progress=$1
    video=$2

    [[ -f "$video" ]] || {
        log "File not found: $video. Removing from list."
        remove_video_path "$video"
        return 0
    }

    aspect_ratio=$(ffprobe -v error -select_streams v:0 -show_entries stream=display_aspect_ratio -of default=nk=1:nw=1 "$video")
    height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$video")
    input_size_bytes=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "$video")
    length=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video")
    original_bitrate=$(ffprobe -v error -show_entries format=bit_rate -of default=nk=1:nw=1 "$video")
    width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$video")
    start_time=$(ffprobe -v error -select_streams v:0 -show_entries frame=best_effort_timestamp_time -of default=nk=1:nw=1 -read_intervals "%+#1" "$video")

    file_out="${video%.*} (x265).${video##*.}"
    mkdir -p "$(dirname "$file_out")"

    bitrate=$(printf "%.0f" "$(echo "$original_bitrate * 0.5 / 1024" | bc -l)")
    bufsize=$(printf "%.0f" "$(echo "$bitrate * 1.5" | bc -l)")
    maxrate=$(printf "%.0f" "$(echo "$bitrate * 2" | bc -l)")

    length=$(printf "%.0f" "$length")
    length_mins=$((length / 60))
    length_secs=$((length % 60))
    threads=$(nproc --all)
    (( threads > 16 )) && threads=16

    estimated_output_size=$(echo "$bitrate * $length / 8 / 1024" | bc -l)
    estimated_output_size=$(printf "%.2f" "$estimated_output_size")
    input_size_mb=$(echo "scale=2; $input_size_bytes / 1024 / 1024" | bc)
    input_size=$(du -m "$video" | cut -f1)

    total_input_size=$((total_input_size + input_size))

    print_video_stats \
        "$progress" \
        "$video" \
        "$file_out" \
        "$input_size_mb" \
        "$original_bitrate" \
        "$aspect_ratio" \
        "$width" \
        "$height" \
        "$length_mins" \
        "$length_secs" \
        "$bitrate" \
        "$estimated_output_size"

    log "Converting $video"

    if run_ffmpeg "$video" "copy" "$file_out" "$bitrate" "$bufsize" "$maxrate" "$threads" "$start_time" ||
       run_ffmpeg "$video" "aac" "$file_out" "$bitrate" "$bufsize" "$maxrate" "$threads" "$start_time"; then
        handle_success "$video" "$file_out" "$input_size"
        return 0
    fi

    google_speech "Video conversion failed." &>/dev/null
    fail "Video conversion failed for: $video"
}

convert_videos() {
    local video count progress total_videos

    total_videos=$(wc -l < "$temp_file")
    count=0

    [[ "$total_videos" -gt 0 ]] || {
        log "No videos to process."
        return 0
    }

    while IFS= read -r -u 9 video; do
        count=$((count + 1))
        progress=$((count * 100 / total_videos))
        convert_single_video "$progress" "$video"
    done 9< "$temp_file"

    log "Total input size: ${total_input_size} MB"
    log "Total output size: ${total_output_size} MB"
    log "Total space saved: ${total_space_saved} MB"
}

kill_related_processes
check_dependencies
convert_videos
