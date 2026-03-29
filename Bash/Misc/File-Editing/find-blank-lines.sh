#!/usr/bin/env bash

# Define color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Display help menu
display_help() {
    echo -e "${CYAN}Usage: $0 -f FILE [-o OUTPUT] [-m MIN] [-M MAX] [-s] [-h]${NC}"
    echo
    echo "Options:"
    echo "  -f FILE       File to scan for consecutive blank lines."
    echo "  -o OUTPUT     Output file for results (optional, defaults to stdout)."
    echo "  -m MIN        Minimum consecutive blank lines to report (default: 1)."
    echo "  -M MAX        Maximum consecutive blank lines to report ('inf' for no limit, default: 'inf')."
    echo "  -s            Sort results by consecutive blank line count."
    echo "  -h, --help    Show this help message and exit."
    exit 0
}

# Parse command-line options
while getopts ":f:o:m:M:sh" opt; do
    case ${opt} in
        f ) file="$OPTARG" ;;
        o ) output_file="$OPTARG" ;;
        m ) min="$OPTARG" ;;
        M ) max="$OPTARG" ;;
        s ) sort_flag=true ;;
        h | --help ) display_help ;;
        \? ) echo -e "${RED}Invalid option: -$OPTARG${NC}" >&2; exit 1 ;;
    esac
done

# Check for mandatory file argument and file existence
if [[ -z "$file" ]]; then
    echo -e "${RED}Error: -f FILE option is required.${NC}" >&2; display_help; exit 1
fi
if [[ ! -f "$file" ]]; then
    echo -e "${RED}File does not exist: $file${NC}" >&2; exit 1
fi

declare -A line_counts
actual_min=0
actual_max=0

# Process the file
line_num=0
blank_count=0
while IFS= read -r line || [[ -n $line ]]; do
    ((line_num++))
    if [[ -z $line ]]; then
        ((blank_count++))
    else
        if (( blank_count >= 1 )); then
            line_counts[$blank_count]+="$((line_num - blank_count))-$((line_num - 1)) "
            actual_min=$((actual_min == 0 ? blank_count : actual_min < blank_count ? actual_min : blank_count))
            actual_max=$((actual_max > blank_count ? actual_max : blank_count))
        fi
        blank_count=0
    fi
done < "$file"
[[ $blank_count -ge 1 ]] && line_counts[$blank_count]+="$((line_num - blank_count + 1))-$line_num" && actual_max=$((actual_max > blank_count ? actual_max : blank_count))

# Validate min and max
max_val=${max:-$actual_max}
[[ $min -gt $actual_max || "${max_val}" -lt $actual_min ]] && echo -e "${YELLOW}No matches found within specified range (min=$min, max=${max:-inf}). Actual min and max consecutive blank lines in file: $actual_min, $actual_max.${NC}" && exit 0

# Optionally sort keys based on flag
keys=(${!line_counts[@]})
[[ "$sort_flag" == true ]] && IFS=$'\n' keys=($(sort -n <<<"${keys[*]}"))

# Output results
{
    for k in "${keys[@]}"; do
        [[ $k -ge $min && ($max == "inf" || $k -le $max) ]] && echo -e "${GREEN}$k consecutive blank lines:${NC}" && echo "${line_counts[$k]}"
    done
} | { [[ -n "$output_file" ]] && cat > "$output_file" || cat; }
