#!/usr/bin/env bash

set -euo pipefail

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
    echo "  --                        End options for paths beginning with a dash."
    echo
    echo "Example:"
    echo "  $0 ./called_script.sh strings_to_check.txt -o results_output.txt"
}

output_file=""
positional_args=()
found_strings=()
not_found_strings=()

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -o|--output-file)
            if [[ $# -lt 2 || -z $2 ]]; then
                printf 'Error: %s requires an output file.\n' "$1" >&2
                exit 1
            fi
            output_file="$2"
            shift 2
            continue
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --)
            shift
            positional_args+=("$@")
            break
            ;;
        -*)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            positional_args+=("$1")
            ;;
    esac
    shift
done

if [[ ${#positional_args[@]} -ne 2 ]]; then
    printf 'Error: Expected a script path and a file with strings.\n' >&2
    show_help >&2
    exit 1
fi
called_script_path=${positional_args[0]}
input_file=${positional_args[1]}
# A bare '-' is a file here, rather than grep's standard input operand.
if [[ "$called_script_path" != /* ]]; then
    called_script_path="./$called_script_path"
fi

if [[ ! -f "$called_script_path" ]] || [[ ! -f "$input_file" ]]; then
    echo "The specified script or input file does not exist." >&2
    exit 2
fi

while IFS= read -r line || [[ -n "$line" ]]; do
    if grep -qF -- "$line" "$called_script_path"; then
        found_strings+=("$line")
    else
        status=$?
        if [[ $status -ne 1 ]]; then
            printf 'Error: Could not search %s.\n' "$called_script_path" >&2
            exit "$status"
        fi
        not_found_strings+=("$line")
    fi
done < "$input_file"

output_results() {
    echo "Strings found:"
    echo "=================="
    for str in "${found_strings[@]}"; do
        printf '%s\n' "$str"
    done

    echo
    echo "Strings not found:"
    echo "=================="
    for str in "${not_found_strings[@]}"; do
        printf '%s\n' "$str"
    done
}

if [[ -n "$output_file" ]]; then
    output_results > "$output_file"
    printf 'Results have been saved to %s\n' "$output_file"
else
    output_results
fi
