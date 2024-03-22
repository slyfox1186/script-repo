#!/usr/bin/env bash

# Initialize variables
total_upvotes=""
upvote_percentage=""

# Function to display help menu
display_help() {
        cat <<EOF
Usage: ${0##*/} [OPTIONS]

Calculate the number of downvotes on a Reddit post.

Options:
  -h, --help                     Display this help message and exit
  -u, --upvotes <number>   Total number of upvotes on the post
  -p, --percentage <number>    Upvote percentage (without the % sign)

Examples:
  ${0##*/} -u 8 -p 83
  ${0##*/} --upvotes 8 --percentage 83

EOF
}

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -u|--total-upvotes)
            total_upvotes="$2"
            shift 2
            ;;
        -p|--percentage)
            upvote_percentage="$2"
            shift 2
            ;;
        -h|--help)
            display_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            display_help
            exit 1
            ;;
    esac
done

# Check if required options are provided
if [[ -z "$total_upvotes" ]] || [[ -z "$upvote_percentage" ]]; then
    echo "Error: Missing required arguments."
    display_help
    exit 1
fi

# Calculations
upvote_percentage_decimal=$(echo "scale=2; $upvote_percentage/100" | bc)
total_votes=$(echo "scale=2; $total_upvotes / $upvote_percentage_decimal" | bc)
total_votes_rounded=$(echo "($total_votes + 0.5)/1" | bc)
downvotes=$(echo "$total_votes_rounded - $total_upvotes" | bc)


# Calculate and display percentage ranges for the first 10 downvotes
echo "Upvote percentage ranges for the first $total_upvotes downvotes:"
for i in $(seq 1 "$total_upvotes"); do
    # Calculating the lower percentage limit for the current number of downvotes
    lower_limit=$(echo "scale=2; $total_upvotes / ($total_upvotes + $i) * 100" | bc)

    # Calculating the lower percentage limit for the next higher number of downvotes
    if [ $i -lt 10 ]; then
        next_lower_limit=$(echo "scale=2; $total_upvotes / ($total_upvotes + $i + 1) * 100" | bc)
    else
        next_lower_limit=0
    fi

    # Display the percentage range
    echo "Downvotes $i: ${lower_limit}% to $(echo "$next_lower_limit + 0.01" | bc)%"
done

# Output the result
echo
echo "Total upvotes: $total_upvotes"
echo "Upvote percentage: $upvote_percentage%"
echo "Calculated downvotes: $downvotes"
