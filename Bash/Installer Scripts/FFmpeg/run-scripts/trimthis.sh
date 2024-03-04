#!/usr/bin/env bash

clear

# Color variables for easier reading and logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

overwrite=0
append_text="-trimmed"
prepend_text=""
file_list=""
single_input_file=""  # Variable for directly passed video file
trim_start=0  # Duration to trim from the start in seconds
trim_end=0  # Duration to trim from the end in seconds
verbose=0  # Verbose flag
processed_files=0  # Track number of processed files

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
    exit 1
}

# Parse options
TEMP=$(getopt -o f:i:a:p:ovh --long file:,input:,start:,end:,append:,prepend:,overwrite,verbose,help -n 'script.sh' -- "$@")
if [ $? != 0 ]; then echo "Failed to parse options... exiting." >&2; exit 1; fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        -f | --file ) file_list="$2"; shift 2 ;;
        -i | --input ) single_input_file="$2"; shift 2 ;;
        --start ) trim_start="$2"; shift 2 ;;
        --end ) trim_end="$2"; shift 2 ;;
        -a | --append ) append_text="$2"; shift 2 ;;
        -p | --prepend ) prepend_text="$2"; shift 2 ;;
        -o | --overwrite ) overwrite=1; shift ;;
        -v | --verbose ) verbose=1; shift ;;
        -h | --help ) usage; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

if [[ -n "$single_input_file" ]]; then
    video_files=("$single_input_file")
elif [[ -n "$file_list" && -f "$file_list" ]]; then
    mapfile -t video_files < "$file_list"
else
    echo -e "${RED}Error: No valid input provided or file does not exist.${NC}"
    usage
    exit 1
fi

for input_file in "${video_files[@]}"; do
    if [[ ! -f "$input_file" ]]; then
        echo -e "${RED}Error: The file '$input_file' does not exist.${NC}"
        continue
    fi

    ((processed_files++))

    echo -e "${GREEN}Processing: '$input_file'${NC}"

    if [ $verbose -eq 1 ]; then
        echo -e "${YELLOW}Verbose mode enabled. Displaying process details.${NC}"
        echo -e "${YELLOW}Trimming $trim_start seconds from the start and $trim_end seconds from the end of the video: '$input_file'${NC}"
    fi

    # Calculate total video duration
    total_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -i "$input_file" | awk '{print $1}')
    target_end_time=$(echo "$total_duration - $trim_end" | bc)
    
    # Format start and end times for ffmpeg
    formatted_start_time=$(echo "$trim_start" | awk '{printf "%02d:%02d:%06.3f", $1/3600, ($1/60)%60, $1%60}')
    formatted_end_time=$(echo "$target_end_time" | awk '{printf "%02d:%02d:%06.3f", $1/3600, ($1/60)%60, $1%60}')

    extension="${input_file##*.}"
    base_name="${input_file%.*}"
    final_output="${prepend_text}${base_name}${append_text}.${extension}"

    # Prompt user before processing
    if [ $verbose -eq 1 ]; then
        read -p "Proceed with trimming? (y/n) " choice
        echo    # Move to a new line
        if [[ $choice != [Yy] ]]; then
            echo -e "${YELLOW}Skipping $input_file based on user choice.${NC}"
            continue
        fi
    fi

    if [ $overwrite -eq 1 ]; then
        temp_output=$(mktemp /tmp/ffmpeg.XXXXXX)
        command="ffmpeg -hide_banner -y -i \"$input_file\" -ss \"$formatted_start_time\" -to \"$formatted_end_time\" -c copy \"$temp_output\""
        eval $command && mv "$temp_output" "$input_file"
        echo -e "${GREEN}Successfully processed and overwritten $input_file${NC}"
    else
        command="ffmpeg -hide_banner -y -i \"$input_file\" -ss \"$formatted_start_time\" -to \"$formatted_end_time\" -c copy \"$final_output\""
        eval $command
        echo -e "${GREEN}Successfully processed $input_file into $final_output${NC}"
    fi
done

if [ $processed_files -gt 0 ]; then
    echo -e "${GREEN}Processing completed.${NC}"
else
    echo -e "${RED}No files were processed.${NC}"
fi
