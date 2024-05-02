#!/usr/bin/env bash

# Check for non-root execution
if [[ "$EUID" -ne 0 ]]; then
  echo "You must run this script as root or with sudo."
  exit 1
fi

# Help menu function
print_help() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo " -h, --help                  Display this help message."
  echo " -a, --age <hours>           Set maximum age in hours since the mirror was last synchronized (default: 24)."
  echo " -c, --country <country>     Country from which to fetch mirrors (default: United States,Canada)."
  echo " -f, --fastest <number>      Fetch the fastest 'n' mirrors (default: 5)."
  echo " -t, --timeout <timeout>     Set download timeout in seconds (default: 1)."
  echo " -l, --latest <number>       Limit to the 'n' most recently synchronized mirrors (default: 100)."
  echo " -p, --protocols <protocols> Comma-separated list of protocols to use (default: http,https)."
  echo " -s, --save <path>           Set the output file path (default: /etc/pacman.d/mirrorlist)."
  echo
  echo "Example:"
  echo " $0 --age 12 --country Germany --fastest 10 --timeout 2 --latest 50 --protocols https --save /path/to/mirrorlist"
}

# Default values
AGE=24
COUNTRY="United States,Canada"
FASTEST=5
TIMEOUT=1
LATEST=100
PROTOCOLS="http,https"
SAVE="/etc/pacman.d/mirrorlist"

# Option parsing
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h|--help) print_help; exit 0 ;;
    -a|--age) AGE=$2; shift ;;
    -c|--country) COUNTRY=$2; shift ;;
    -f|--fastest) FASTEST=$2; shift ;;
    -t|--timeout) TIMEOUT=$2; shift ;;
    -l|--latest) LATEST=$2; shift ;;
    -p|--protocols) PROTOCOLS=$2; shift ;;
    -s|--save) SAVE=$2; shift ;;
    *) echo "Invalid option: $1" 1>&2; print_help; exit 1 ;;
  esac
  shift
done

prompt_user() {
  clear
  echo "You can leave a value as it's default by leaving the prompt blank and pressing enter."
  echo
  read -p "Set how many mirrors to test (default: 100): " PROMPT_LATEST
  read -p "Set how many of the fastest mirrors to keep (default: 5): " PROMPT_FASTEST
  read -p "Set the output file path (default: /etc/pacman.d/mirrorlist): " PROMPT_SAVE
  [[ -n "$PROMPT_LATEST" ]] && LATEST="$PROMPT_LATEST"
  [[ -n "$PROMPT_FASTEST" ]] && FASTEST="$PROMPT_FASTEST"
  [[ -n "$PROMPT_SAVE" ]] && SAVE="$PROMPT_SAVE"
}

echo
read -p "Do you want to manually set the LATEST and FASTEST values? (y/n): " prompt_choice
case "$prompt_choice" in
  [yY]*) prompt_user ;;
  [nN]*) ;;
esac

clear
# Reflector command with configurable options
reflector --age "$AGE" \
          --country "$COUNTRY" \
          --fastest "$FASTEST" \
          --download-timeout "$TIMEOUT" \
          --latest "$LATEST" \
          --protocol "$PROTOCOLS" \
          --save "$SAVE" \
          --sort rate \
          --verbose
