#!/usr/bin/env bash

# Color variables for easier reading and logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

overwrite=0
append_text="-trimmed"
prepend_text=""
file_list=""
single_input_file=""
trim_start=0
trim_end=0
verbose=0
batch_mode=0

# Function to display usage
usage() {
    echo -e "${GREEN}Usage: $0 [-f <file_list> | -i <input_file>] [--start <trim_start_seconds>] [--end <trim_end_seconds>] [--append <append_text>] [--prepend <prepend_text>] [--overwrite] [--verbose]${NC}"
    echo
    echo -e "Options:"
    echo -e "  -h, --help             Display this help message."
    echo -e "  -f, --file             Specify the path to the text file containing the list of video files."
    echo -e "  -i, --input            Specify the path to a single video file directly."
    echo -e "      --start            Duration in seconds to trim from the start of the video."
    echo -e "      --end              Duration in seconds to trim from the end of the video."
    echo -e "  -a, --append           Specify text to append to the output file name. Ignored if --overwrite is used."
    echo -e "  -p, --prepend          Specify text to prepend to the output file name. Ignored if --overwrite is used."
    echo -e "  -o, --overwrite        Overwrite the input file instead of creating a new one."
    echo -e "  -v, --verbose          Enable verbose output."
    echo
    echo "Examples:"
    echo "$0 -v -i \"video.mp4\""
    echo "$0 -o -v -i \"video.mp4\""
    echo "$0 -f \"video_list.txt\""
    exit 1
}

# Remove log file if it exists
[[ -f video-processing.log ]] && rm video-processing.log

# Parse options
TEMP=$(getopt -o f:i:a:p:ovh --long file:,input:,start:,end:,append:,prepend:,overwrite,verbose,help -n 'script.sh' -- "$@")
if [ $? != 0 ]; then echo "Failed to parse options... exiting." >&2; exit 1; fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        -f | --file ) file_list="$2"; batch_mode=1; shift 2 ;;
        -i | --input ) single_input_file="$2"; shift 2 ;;
        --start ) trim_start="$2"; shift 2 ;;
        --end ) trim_end="$2"; shift 2 ;;
        -a | --append ) append_text="$2"; shift 2 ;;
        -p | --prepend ) prepend_text="$2"; shift 2 ;;
        -o | --overwrite ) overwrite=1; append_text=""; prepend_text=""; shift ;;
        -v | --verbose ) verbose=1; shift ;;
        -h | --help ) usage; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

# Function to prompt for input file
prompt_for_input() {
    while true; do
        read -p "Enter the path to the input video file (or 'q' to quit): " single_input_file
        if [[ "$single_input_file" == "q" ]]; then
            echo "Quitting..."
            exit 0
        elif [[ -f "$single_input_file" ]]; then
            video_files+=("$single_input_file")
            clear
            break
        else
            echo -e "${RED}Error: The file $single_input_file does not exist. Please try again.${NC}"
        fi
    done
}

# Function to process a single video
process_video() {
    local input_file="$1"
    echo -e "${GREEN}Processing: $input_file${NC}"

    # Calculate total video duration
    local total_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -i "$input_file" | awk '{print $1}')

    # Calculate start and end keyframe timestamps
    local formatted_start_time formatted_end_time
    if [[ $trim_start -gt 0 ]]; then
        formatted_start_time=$(ffprobe -v error -select_streams v -of csv=p=0 -show_entries frame=best_effort_timestamp_time -read_intervals $trim_start%+$trim_start -i "$input_file" | head -n1 | tr -d '[:space:],' | grep -E '^[0-9]+(\.[0-9]+)?$')
        if [[ -z "$formatted_start_time" ]]; then
            echo -e "${YELLOW}No keyframe found near start time $trim_start, using the exact time instead.${NC}"
            formatted_start_time=$trim_start
        fi
    else
        formatted_start_time=$(ffprobe -v error -of default=noprint_wrappers=1:nokey=1 -select_streams v:0 -skip_frame nokey -show_frames -show_entries frame=pkt_dts_time "$input_file" |
                               grep -E '^[0-9]+(\.[0-9]+)?$' | head -n1)
    fi

    if [[ $trim_end -gt 0 ]]; then
        local target_end_time=$(echo "$total_duration - $trim_end" | bc)
        formatted_end_time=$(ffprobe -v error -select_streams v -of csv=p=0 -show_entries frame=best_effort_timestamp_time -read_intervals -$trim_end%-$trim_end -i "$input_file" |
                             sort -rV | head -n1 | tr -d '[:space:],' | grep -E '^[0-9]+(\.[0-9]+)?$')
        if [[ -z "$formatted_end_time" ]]; then
            echo -e "${YELLOW}No keyframe found near end time $trim_end, using the exact time instead.${NC}"
            formatted_end_time="$target_end_time"
        fi
    else
        formatted_end_time="$total_duration"
    fi

    # Validate timestamps
    if [[ ! "$formatted_start_time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "${RED}Error: Invalid start time format: $formatted_start_time${NC}"
        return 1
    fi

    if [[ ! "$formatted_end_time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "${RED}Error: Invalid end time format: $formatted_end_time${NC}"
        return 1
    fi

    if [[ "$verbose" -eq 1 ]]; then
        echo -e "${YELLOW}Trimming from $formatted_start_time to $formatted_end_time.${NC}"
    fi

    local base_name="${input_file%.*}"
    local extension="${input_file##*.}"
    local final_output="${prepend_text}${base_name}${append_text}.${extension}"
    if [ $overwrite -eq 1 ]; then
        final_output="$input_file"
    fi

    local trim_start_cmd trim_end_cmd
    [[ -n "$formatted_start_time" ]] && trim_start_cmd="-ss $formatted_start_time"
    [[ -n "$formatted_end_time" ]] && trim_end_cmd="-to $formatted_end_time"

    # Prompt user before processing in interactive mode
    if [[ "$verbose" -eq 1 && "$batch_mode" -eq 0 ]]; then
        read -p "Proceed with trimming? (y/n) " choice
        echo    # Move to a new line
        if [[ "$choice" != [Yy] ]]; then
            echo -e "${YELLOW}Skipping $input_file based on user choice.${NC}"
            return
        fi
    fi

    local temp_output_dir="$(dirname "$input_file")"
    if [[ $overwrite -eq 1 ]]; then
        local temp_output=$(mktemp "$temp_output_dir/ffmpeg.XXXXXX.$extension")
        local command="ffmpeg -hide_banner $trim_start_cmd -y -i \"$input_file\" $trim_end_cmd -c copy \"$temp_output\""
        if eval $command && mv "$temp_output" "$input_file"; then
            echo -e "${GREEN}Successfully processed and overwritten $input_file${NC}\\n"
        else
            echo -e "${RED}Failed to process $input_file${NC}\\n"
            return
        fi
    else
        local command="ffmpeg -hide_banner $trim_start_cmd -y -i \"$input_file\" $trim_end_cmd -c copy \"$final_output\""
        if eval $command; then
            echo -e "${GREEN}Successfully processed $input_file into $final_output${NC}\\n"
        else
            echo -e "${RED}Failed to process $input_file${NC}\\n"
            return
        fi
    fi
}

# Main processing loop
main() {
    while true; do
        video_files=()
        if [[ -z "$single_input_file" && -z "$file_list" ]]; then
            prompt_for_input
        elif [[ -n "$single_input_file" ]]; then
            video_files+=("$single_input_file")
        elif [[ -n "$file_list" && -f "$file_list" ]]; then
            mapfile -t video_files < "$file_list"
        else
            echo -e "${RED}Error: No input video or file list provided, or file does not exist.${NC}"
            usage
        fi

        for input_file in "${video_files[@]}"; do
            if [[ ! -f "$input_file" ]]; then
                echo -e "${RED}Error: The file $input_file does not exist.${NC}"
                continue
            fi
            process_video "$input_file"
            # In interactive mode, prompt user to continue
            if [[ "$batch_mode" -eq 0 ]]; then
                read -p "Press Enter to continue..."
                clear
            fi
        done
        single_input_file="" # Reset single_input_file for next iteration
        # If in batch mode, exit after processing all files
        if [[ "$batch_mode" -eq 1 ]]; then
            break
        fi
    done

    echo -e "${GREEN}Processing completed.${NC}"
}

main
