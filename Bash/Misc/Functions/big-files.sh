#!/usr/bin/env bash

# Pass the number of folder/files you want to populate results for
# Example: To get the 5 largest folders and files in the directory execute: big_files 5

big_files() {
  local num_results full_path size folder file suffix
  # Check if an argument is provided
  if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    num_results=$1
  else
    # Prompt the user to enter the number of results
    read -p "Enter the number of results to display: " num_results
    while ! [[ "$num_results" =~ ^[0-9]+$ ]]; do
      read -p "Invalid input. Enter a valid number: " num_results
    done
  fi
  echo "Largest Folders:"
  du -h -d 1 2>/dev/null | sort -hr | head -n "$num_results" | while read -r size folder; do
    full_path=$(realpath "$folder")
    suffix="${size: -1}"
    size=$(echo "${size%?}" | awk '{printf "%d.%02d", $1, int(($1-int($1))*100)}')
    printf "%-80s %14s%s\n" "$full_path" "$size" "$suffix"
  done | column -t
  echo
  echo "Largest Files:"
  find . -type f -exec du -h {} + 2>/dev/null | sort -hr | head -n "$num_results" | while read -r size file; do
    full_path=$(realpath "$file")
    suffix="${size: -1}"
    size=$(echo "${size%?}" | awk '{printf "%d.%02d", $1, int(($1-int($1))*100)}')
    printf "%-80s %14s%s\n" "$full_path" "$size" "$suffix"
  done | column -t
}

big_files 5
