#!/usr/bin/env bash
clear

# Color variables for easier reading and logging
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Initialize variables
overwrite=0
append_text="-corrected"
prepend_text=""
list=""

# Function to display usage
usage() {
echo -e "${GREEN}Usage: $0 [-f <path_to_file_list>] [--append <append_text>] [--prepend <prepend_text>] [--overwrite]${NC}"
echo
echo -e "Options:"
echo -e "  -h, --help             Display this help message."
echo -e "  -f, --file             Specify the path to the file containing the list of video files."
echo -e "  -a, --append           Specify text to append to the output file name. Ignored if --overwrite is used."
echo -e "  -p, --prepend          Specify text to prepend to the output file name. Ignored if --overwrite is used."
echo -e "  -o, --overwrite        Overwrite the input file instead of creating a new one."
exit 1
}

# Parse options
TEMP=$(getopt -o f:a:p:oh --long file:,append:,prepend:,overwrite,help -n 'script.sh' -- "$@")
if [ $? != 0 ]; then echo "Failed to parse options... exiting." >&2; exit 1; fi

# Note the quotes around `$TEMP`: they are essential!
eval set -- "$TEMP"

# Extract options and their arguments into variables
while true; do
case "$1" in
    -f | --file ) list="$2"; shift 2 ;;
    -a | --append ) append_text="$2"; shift 2 ;;
    -p | --prepend ) prepend_text="$2"; shift 2 ;;
    -o | --overwrite ) overwrite=1; append_text=""; prepend_text=""; shift ;;
    -h | --help ) usage; shift ;;
    -- ) shift; break ;;
    * ) break ;;
esac
done

# Check if the list was provided as an argument, otherwise assume the first argument is the list
if [[ -z "$list" && -n "$1" ]]; then
list="$1"
fi

# Check for mandatory options or arguments
if [[ -z "$list" ]]; then
echo -e "${RED}Error: Path to file list not provided.${NC}"
usage
exit 1
fi

# Verify the input file exists
if [[ ! -f "$list" ]]; then
echo -e "${RED}Error: The file $list does not exist.${NC}"
exit 1
fi

mapfile -t filesArray < "$list"

total_count=${#filesArray[@]}
count=0
echo -e "${GREEN}Processing ${total_count} files...${NC}"

for filename in "${filesArray[@]}"; do
((count++))
temp_output="${filename}.temp"

if [[ -f "$temp_output" ]]; then
    echo -e "${RED}Stale temporary file detected: $temp_output${NC}"
    read -p "Do you want to delete the temporary file? (y/N): " choice
    case "${choice,,}" in
        y|yes) rm "$temp_output"; echo -e "${GREEN}Temporary file deleted.${NC}";;
        *)     echo -e "${RED}Skipping $filename due to existing temporary file.${NC}"; continue;;
    esac
fi

if [[ ! -f "$filename" ]]; then
    echo -e "${RED}[${count}/${total_count}] Error: File '$filename' does not exist.${NC}"
    continue
fi

echo -e "${GREEN}[${count}/${total_count}] Processing: $filename${NC}"

first_keyframe=$(ffprobe -v error -of default=noprint_wrappers=1:nokey=1 -select_streams v:0 -skip_frame nokey -show_frames -show_entries frame=pkt_dts_time -i "$filename" | head -n 1)
formatted_keyframe=$(echo "$first_keyframe" | awk '{printf "%02d:%02d:%06.3f", $1/3600, ($1/60)%60, $1%60}')

extension="${filename##*.}"

if [ $overwrite -eq 1 ]; then
    output="$filename"
else
    base_name="${filename%.*}"
    final_output="${prepend_text}${base_name}${append_text}.${extension}"
fi

ffmpeg -hide_banner -y -i "$filename" -ss "$formatted_keyframe" -c copy -f mp4 "$temp_output"

if [ $? -eq 0 ]; then
    mv "$temp_output" "${final_output:-$output}"
    if [ $overwrite -eq 1 ]; then
        echo -e "${GREEN}Successfully processed and overwritten $filename${NC}"
    else
        echo -e "${GREEN}Successfully processed $filename${NC}"
    fi
else
    echo -e "${RED}Failed to process $filename${NC}"
    [ -f "$temp_output" ] && rm "$temp_output"
fi
done

echo -e "${GREEN}Processing completed.${NC}"
