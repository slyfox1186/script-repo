#!/Usr/bin/env bash

display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help           Display this help menu"
    echo "  -i, --input          Input video path (full or relative)"
    echo "  -o, --output         Output video path (full or relative)"
    echo "  -t, --target-size    Target size in megabytes (MB) (default: 500)"
    echo "  --original-size      Original size in megabytes (MB) (default: 1000)"
    echo "  -a, --audio-rate     Audio bitrate in kilobits per second (kbps) (default: 128)"
    echo "  -d, --duration       Duration in seconds (default: 3600)"
    echo "  -l, --log-file       Log file path (default: resize.log)"
}

target_size_mb=1500
original_size_mb=2480
audio_bitrate_kbps=128
duration_seconds=1410
log_file="resize.log"

    case $1 in
        -h|--help)
            display_help
            exit 0
            ;;
        -i|--input)
            input_file="$2"
            shift 2
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        -t|--target-size)
            target_size_mb="$2"
            shift 2
            ;;
        --original-size)
            original_size_mb="$2"
            shift 2
            ;;
        -a|--audio-rate)
            audio_bitrate_kbps="$2"
            shift 2
            ;;
        -d|--duration)
            duration_seconds="$2"
            shift 2
            ;;
        -l|--log-file)
            log_file="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            display_help
            exit 1
            ;;
    esac
done

prompt_for_value() {
    local value_name=$1
    local default_value=$2
    local prompt_message=$3

    if [[ -z "$!value_name" ]]; then
        read -p "$prompt_message [$default_value]: " user_input
        eval "$value_name=$user_input:-$default_value"
    fi
}

prompt_for_value "input_file" "" "Enter the input video path"
prompt_for_value "output_file" "" "Enter the output video path"

echo "Confirmed Values:"
echo "  Input File: $input_file"
echo "  Output File: $output_file"
echo "  Target Size (MB): $target_size_mb"
echo "  Original Size (MB): $original_size_mb"
echo "  Audio Bitrate (kbps): $audio_bitrate_kbps"
echo "  Duration (seconds): $duration_seconds"
echo "  Log File: $log_file"
echo

if [[ ! -f "$input_file" ]]; then
    echo "Input file does not exist: $input_file"
    exit 1
fi

if [[ $target_size_mb -le 0 || $original_size_mb -le 0 || $audio_bitrate_kbps -le 0 || $duration_seconds -le 0 ]]; then
    echo "Invalid argument values. Please provide positive numbers."
    exit 1
fi

get_video_stats() {
    video_file="$1"

    size_mb=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "$video_file" | awk '{print $1 / 1024 / 1024}')

    audio_bitrate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$video_file" | awk '{print int($1 / 1000)}')

    video_bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$video_file" | awk '{print int($1 / 1000)}')

    echo "$size_mb $audio_bitrate $video_bitrate"
}

read size_mb audio_bitrate video_bitrate <<< $(get_video_stats "$input_file")

total_bitrate_kbps=$((audio_bitrate + video_bitrate))
target_total_bitrate_kbps=$(echo "scale=0; $total_bitrate_kbps * $target_size_mb / $size_mb" | bc)
target_video_bitrate_kbps=$(echo "$target_total_bitrate_kbps - $audio_bitrate_kbps" | bc)

if [[ $(echo "$target_video_bitrate_kbps < 0" | bc -l) -eq 1 ]]; then
    echo "Calculated video bitrate is negative. Adjusting to minimum feasible value."
fi

resized_size_mb=$target_size_mb
resized_audio_bitrate_kbps=$audio_bitrate_kbps
resized_video_bitrate_kbps=$target_video_bitrate_kbps

echo "Input Video Stats:"
echo "  Size: $size_mb MB"
echo "  Audio Bitrate: $audio_bitrate kbps"
echo "  Video Bitrate: $video_bitrate kbps"
echo
echo "Resized Video Stats:"
echo "  Size: $resized_size_mb MB"
echo "  Audio Bitrate: $resized_audio_bitrate_kbps kbps"
echo "  Video Bitrate: $resized_video_bitrate_kbps kbps"
echo

size_diff_percent=$(echo "scale=2; (($resized_size_mb - $size_mb) / $size_mb) * 100" | bc)
audio_bitrate_diff_percent=$(echo "scale=2; (($resized_audio_bitrate_kbps - $audio_bitrate) / $audio_bitrate) * 100" | bc)
video_bitrate_diff_percent=$(echo "scale=2; (($resized_video_bitrate_kbps - $video_bitrate) / $video_bitrate) * 100" | bc)

echo "Percentage Differences:"
echo "  Size: $size_diff_percent%"
echo "  Audio Bitrate: $audio_bitrate_diff_percent%"
echo "  Video Bitrate: $video_bitrate_diff_percent%"
echo

read -p "Do you want to proceed with the FFmpeg processing? (y/n): " confirmation

if [[ $confirmation =~ ^[Yy]$ ]]; then
    echo -e "\\nFFmpeg Command:\\n"
    echo "ffmpeg -i \"$input_file\" -b:v $target_video_bitrate_kbpsk -b:a $audio_bitrate_kbpsk -t $duration_seconds \"$output_file\""
    echo

    echo "Resizing video..."
    echo
    ffmpeg -i "$input_file" -b:v $target_video_bitrate_kbpsk -b:a $audio_bitrate_kbpsk -t $duration_seconds "$output_file" 2>&1 | tee "$log_file"
    echo "Video resizing completed. Log file: $log_file"
else
    echo "FFmpeg processing aborted."
    exit 0
fi
