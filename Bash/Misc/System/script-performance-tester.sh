#!/usr/bin/env bash

# Default values
PYTHON_SCRIPT=""
SCRIPT_ARGS=""
PERFORMANCE_LOG="python-performance.log"
CREATE_LOG=false

# Function to display help menu
display_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -s, --script <script>        Path to the Python script to measure"
    echo "  -a, --args <arguments>       Comma-separated arguments to pass to the Python script"
    echo "  -l, --log <log_file>         Path to the performance log file (default: python-performance.log)"
    echo "  -c, --create-log             Create the performance log file"
    echo "  -h, --help                   Display this help menu"
    echo
    echo "Example: ./$0 --script domain_lookup.py -a google.com,yahoo.com"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--script) PYTHON_SCRIPT="$2"; shift ;;
        -a|--args) SCRIPT_ARGS="$2"; shift ;;
        -l|--log) PERFORMANCE_LOG="$2"; shift ;;
        -c|--create-log) CREATE_LOG=true ;;
        -h|--help) display_help; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if the Python script is provided
if [[ -z "$PYTHON_SCRIPT" ]]; then
    echo "Error: Python script is not provided. Use the -s or --script option to specify the script."
    exit 1
fi

# Check if the Python script exists
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    echo "Error: Python script '$PYTHON_SCRIPT' does not exist."
    exit 1
fi

# Measure the performance
start_time=$(date +%s.%N) # Capture start time with nanosecond precision

if [[ -n "$SCRIPT_ARGS" ]]; then
    IFS=',' read -ra args_array <<< "$SCRIPT_ARGS"
    execute_this=("$PYTHON_SCRIPT" "${args_array[@]}")
    python3 "${execute_this[@]}"
else
    python3 "$PYTHON_SCRIPT"
fi
end_time=$(date +%s.%N) # Capture end time with nanosecond precision

# Calculate the duration in seconds with 6 decimal places using bc
duration=$(echo "$end_time - $start_time" | bc -l | awk '{printf "%.6f\n", $0}')

# Get the current git commit hash
commit_hash=$(git rev-parse HEAD)

# Log the performance along with the current git commit hash if CREATE_LOG is true
if [[ "$CREATE_LOG" = true ]]; then
    echo "$(date +%m-%d-%Y\ %H:%M:%S-%p) | Commit: $commit_hash | Duration: $duration seconds" >> $PERFORMANCE_LOG
    echo "Performance logged. Duration: $duration seconds | Commit: $commit_hash"
else
    echo "Duration: $duration seconds | Commit: $commit_hash"
fi
