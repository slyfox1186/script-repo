#!/bin/bash
# monitor.sh - Monitor a directory recursively using inotifywait,
# and warn if the number of directories nears the system's max inotify watches.
#
# Usage: bash monitor.sh [-a] -d <directory>
#   -a : (Optional) Include attribute change events (attrib) in monitoring.
#   -d : Specify the directory to monitor.

# Check if inotifywait is installed
if ! command -v inotifywait &> /dev/null; then
    echo "Error: inotifywait is not installed. Please install inotify-tools."
    exit 1
fi

# Default values for options
monitor_dir=""
all_mode=false

# Print usage message and exit
usage() {
    echo "Usage: $0 [-a] -d <directory>"
    exit 1
}

# Parse command line options
while getopts ":ad:" opt; do
  case $opt in
    a)
      all_mode=true
      ;;
    d)
      monitor_dir="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage
      ;;
  esac
done

# Check if directory was provided
if [ -z "$monitor_dir" ]; then
    usage
fi

# Validate that the given directory exists
if [ ! -d "$monitor_dir" ]; then
    echo "Error: '$monitor_dir' is not a valid directory."
    exit 1
fi

echo "Monitoring directory: $monitor_dir"
if [ "$all_mode" = true ]; then
    echo "All mode enabled: Including attribute (attrib) events."
fi

# Set events to monitor. If all_mode is true, include 'attrib'.
if [ "$all_mode" = true ]; then
    events="modify,create,delete,move,attrib"
else
    events="modify,create,delete,move"
fi

# Retrieve the maximum number of inotify watches allowed
max_watches=$(cat /proc/sys/fs/inotify/max_user_watches)
if [ -z "$max_watches" ]; then
    echo "Error: Unable to retrieve max_user_watches."
    exit 1
fi

echo "Max inotify watches: $max_watches"

# Count the number of directories under the monitor directory (including subdirectories)
num_dirs=$(find "$monitor_dir" -type d | wc -l)
echo "Number of directories found: $num_dirs"

# Check if the number of directories exceeds 80% of the maximum watches.
# Using integer arithmetic: max_watches * 8 / 10.
if (( num_dirs > max_watches * 8 / 10 )); then
    echo "Warning: The number of directories ($num_dirs) exceeds 80% of the maximum allowed inotify watches ($max_watches)."
    echo "Consider increasing the inotify watch limit (e.g., via 'sudo sysctl fs.inotify.max_user_watches=<new_value>')."
fi

# Start monitoring the directory recursively for file events.
echo "Starting to monitor directory: $monitor_dir with events: $events"
inotifywait -m -r -e "$events" "$monitor_dir" |
while read -r directory events filename; do
    echo "Event detected: $events in ${directory}${filename}"
done


