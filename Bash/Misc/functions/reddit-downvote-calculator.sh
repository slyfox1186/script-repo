#!/usr/bin/env bash

# Function to calculate the number of downvotes on a Reddit post
calculate_downvotes() {
    # Declare an associative array to hold the named arguments
    declare -A args

    # Parse named arguments
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -u|--upvotes)
                args["total_upvotes"]="$2"
                shift 2
                ;;
            -p|--percentage)
                args["upvote_percentage"]="$2"
                shift 2
                ;;
            -h|--help)
                display_help
                return 0
                ;;
            *)
                echo "Error: Unknown option '$1'"
                display_help
                return 1
                ;;
        esac
    done

    # Check if required arguments are provided
    if [[ -z "${args["total_upvotes"]}" ]] || [[ -z "${args["upvote_percentage"]}" ]]; then
        echo "Error: Missing required arguments."
        display_help
        return 1
    fi

    # Access named arguments from the associative array
    local total_upvotes="${args["total_upvotes"]}"
    local upvote_percentage="${args["upvote_percentage"]}"

    # Calculations
    upvote_percentage_decimal=$(echo "scale=2; $upvote_percentage/100" | bc)
    total_votes=$(echo "scale=2; $total_upvotes / $upvote_percentage_decimal" | bc)
    total_votes_rounded=$(echo "($total_votes + 0.5)/1" | bc)
    downvotes=$(echo "$total_votes_rounded - $total_upvotes" | bc)

    # Calculate and display percentage ranges for the first 10 downvotes
    echo -e "Upvote percentage ranges for the first $total_upvotes downvotes:"
    for (( i = 1; i <= total_upvotes; i++ )); do
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
}

# Function to display help menu
display_help() {
    cat <<EOF
Usage: ${FUNCNAME[0]} [OPTIONS]

Calculate the number of downvotes on a Reddit post.

Options:
  -u, --upvotes <number>         Total number of upvotes on the post
  -p, --percentage <number>      Upvote percentage (without the % sign)
  -h, --help                     Display this help message and exit

Examples:
  ${FUNCNAME[0]} --upvotes 8 --percentage 83

EOF
}

# Uncomment the following line if you want to call the function with provided arguments
#calculate_downvotes "$@"
