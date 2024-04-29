#!/usr/bin/env bash

# Function to calculate the number of downvotes on a Reddit post
calculate_downvotes() {
    # Declare an associative array to hold the named arguments
    declare -A args

    # Parse named arguments
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -u|--upvotes)
                args['total_upvotes']="$2"
                shift 2
                ;;
            -p|--percentage)
                args['upvote_percentage']="$2"
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
    if [[ -z "${args['total_upvotes']}" ]] || [[ -z "${args['upvote_percentage']}" ]]; then
        echo "Error: Missing required arguments."
        display_help
        return 1
    fi

    # Access named arguments from the associative array
    local total_upvotes="${args['total_upvotes']}"
    local upvote_percentage="${args['upvote_percentage']}"

    # Calculations
    upvote_percentage_decimal=$(echo "scale=4; $upvote_percentage/100" | bc)
    downvotes=$(echo "scale=0; ($total_upvotes / $upvote_percentage_decimal) - $total_upvotes" | bc)

    # Determine the maximum number of downvotes to display
    max_downvotes=$(( downvotes > 10 ? downvotes : 10 ))

    # Calculate and display percentage ranges for the specified number of downvotes
    echo -e "Upvote percentage ranges for the first $max_downvotes downvotes:"
    for (( i = 1; i <= max_downvotes; i++ )); do
        # Calculating the lower percentage limit for the current number of downvotes
        lower_limit=$(echo "scale=4; $total_upvotes / ($total_upvotes + $i) * 100" | bc)

        # Calculating the lower percentage limit for the next higher number of downvotes
        next_lower_limit=$(echo "scale=4; $total_upvotes / ($total_upvotes + $i + 1) * 100" | bc)

        # Display the percentage range
        printf "Downvotes %d: %.2f%% to %.2f%%\n" $i $lower_limit $next_lower_limit
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
