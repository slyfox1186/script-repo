#!/usr/bin/env bash

# Function to display help information
show_help() {
    echo "Usage: $0 <path_to_called_script> <file_with_strings> [-o|--output-file <output_file>] [-h|--help]"
    echo
    echo "This script checks each line from the specified file to see if it exists in the called script."
    echo "It categorizes strings into 'found' and 'not found' groups."
    echo "Arguments:"
    echo "  <path_to_called_script>    Path to the script whose contents will be searched."
    echo "  <file_with_strings>        File containing strings to search for in the called script."
    echo "  -o, --output-file <file>   Optional. Specify an output file to save the search results."
    echo "  -h, --help                 Display this help message and exit."
    echo
    echo "Example:"
    echo "  $0 ./called_script.sh strings_to_check.txt -o results_output.txt"
}

# Initialize variables
called_script_path=""
input_file=""
output_file=""
found_strings=()
not_found_strings=()

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -o|--output-file)
            output_file="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            # Assuming positional arguments: called_script_path and input_file
            if [[ -z "$called_script_path" ]]; then
                called_script_path="$1"
            elif [[ -z "$input_file" ]]; then
                input_file="$1"
            else
                echo "Unexpected extra argument: $1" >&2
                show_help
                exit 1
            fi
            ;;
    esac
    shift
done

# Validate required arguments
if [[ -z "$called_script_path" ]] || [[ -z "$input_file" ]]; then
    echo "Missing required arguments." >&2
    show_help
    exit 1
fi

# Ensure the called script and input file exist
if [[ ! -f "$called_script_path" ]] || [[ ! -f "$input_file" ]]; then
    echo "The specified script or input file does not exist." >&2
    exit 2
fi

# Check each line from the file in the called script
while IFS= read -r line; do
    if grep -qF -- "$line" "$called_script_path"; then
        found_strings+=("$line")
    else
        not_found_strings+=("$line")
    fi
done < "$input_file"

# Function to output results
output_results() {
    echo "Strings found:"
    echo "=================="
    for str in "${found_strings[@]}"; do
        echo "$str"
    done

    echo
    echo "Strings not found:"
    echo "=================="
    for str in "${not_found_strings[@]}"; do
        echo "$str"
    done
}

# Write results to the specified output file or stdout
if [[ -n "$output_file" ]]; then
    output_results > "$output_file"
    echo "Results have been saved to $output_file"
else
    output_results
fi
