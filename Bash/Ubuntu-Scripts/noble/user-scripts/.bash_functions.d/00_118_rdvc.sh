#!/usr/bin/env bash

# Reddit Downvote Calculator
rdvc() {
    declare -A args
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -u|--upvotes) args["total_upvotes"]="$2"; shift 2 ;;
            -p|--percentage) args["upvote_percentage"]="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: rdvc [OPTIONS]"
                echo "Calculate Reddit downvotes based on total upvotes and upvote percentage."
                echo
                echo "Options:"
                echo "  -u, --upvotes       Set the total number of upvotes"
                echo "  -p, --percentage    Set the upvote percentage"
                echo "  -h, --help          Display this help message"
                echo
                return 0
                ;;
            *)
                echo "Error: Unknown option '$1'."
                echo "Use -h or --help for usage information."
                return 1
                ;;
        esac
    done

    if [[ -z ${args["total_upvotes"]} || -z ${args["upvote_percentage"]} ]]; then
        echo "Error: Missing required arguments."
        echo "Use -h or --help for usage information."
        return 1
    fi

    local total_upvotes="${args["total_upvotes"]}"
    local upvote_percentage="${args["upvote_percentage"]}"

    upvote_percentage_decimal=$(bc <<< "scale=2; $upvote_percentage / 100")
    total_votes=$(bc <<< "scale=2; $total_upvotes / $upvote_percentage_decimal")
    total_votes_rounded=$(bc <<< "($total_votes + 0.5) / 1")
    downvotes=$(bc <<< "$total_votes_rounded - $total_upvotes")

    echo -e "Upvote percentage ranges for the first $total_upvotes downvotes:"
    for ((i=1; i<=total_upvotes; i++)); do
        lower_limit=$(bc <<< "scale=2; $total_upvotes / ($total_upvotes + $i) * 100")
        if [[ $i -lt $total_upvotes ]]; then
            next_lower_limit=$(bc <<< "scale=2; $total_upvotes / ($total_upvotes + $i + 1) * 100")
            next_lower_limit_adjusted=$(bc <<< "scale=2; $next_lower_limit + 0.01")
            echo "Downvotes $i: ${lower_limit}% to $next_lower_limit_adjusted%"
        else
            echo "Downvotes $i: ${lower_limit}% and lower"
        fi
    done

    echo
    echo "Total upvotes: $total_upvotes"
    echo "Upvote percentage: $upvote_percentage%"
    echo "Calculated downvotes: $downvotes"
}
