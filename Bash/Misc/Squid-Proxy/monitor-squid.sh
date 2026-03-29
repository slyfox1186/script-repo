#!/usr/bin/env bash

# Default path to the Squid access log
LOG_FILE="/var/log/squid/access.log"

# Ensure the log file exists
if [[ ! -f "$LOG_FILE" ]]; then
  echo "Error: Log file does not exist: $LOG_FILE"
  exit 1
fi

# Function to show usage information
usage() {
  echo "Usage: $(basename "$0") [OPTION]"
  echo "Monitor Squid proxy logs in real time."
  echo
  echo "Options:"
  echo "  -h, --help         Display this help message"
  echo "  -4, --show-400     Show only HTTP status codes starting with 400"
  exit 0
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -4|--show-400)
      SHOW_400=true
      shift
      ;;
    *)
      echo "Error: Invalid option: $1"
      usage
      ;;
  esac
done

# Tail the log file and optionally filter for HTTP status codes starting with 400
if [[ -n "$SHOW_400" ]]; then
  tail -f "$LOG_FILE" | grep --line-buffered -E "HTTP\/1\.[01]\" 40[0-9]"
else
  tail -f "$LOG_FILE"
fi
