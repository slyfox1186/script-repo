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
    echo
}

# Default values
age=24
country="United States,Canada"
fastest=5
timeout=1
latest=100
protocols="http,https"
save="/etc/pacman.d/mirrorlist"

# Option parsing
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -a|--age) age=$2; shift ;;
        -c|--country) country=$2; shift ;;
        -f|--fastest) fastest=$2; shift ;;
        -t|--timeout) timeout=$2; shift ;;
        -l|--latest) latest=$2; shift ;;
        -p|--protocols) protocols=$2; shift ;;
        -s|--save) save=$2; shift ;;
        *) echo "Invalid option: $1" 1>&2; print_help; exit 1 ;;
    esac
    shift
done

prompt_user() {
    local prompt_fastest prompt_latest prompt_save
    clear
    echo "You can leave a value as it's default by leaving the prompt blank and pressing enter."
    echo
    read -p "Set how many mirrors to test (default: 100): " prompt_latest
    read -p "Set how many of the fastest mirrors to keep (default: 5): " prompt_fastest
    read -p "Set the output file path (default: /etc/pacman.d/mirrorlist): " prompt_save
    read -p "Set the countries sparated by commas (default: United States,Canada): " prompt_country
    read -p "Set the protocol [http|https|http,https] (default: http,https): " prompt_protocols
    [[ -n "$prompt_latest" ]] && latest="$prompt_latest"
    [[ -n "$prompt_fastest" ]] && fastest="$prompt_fastest"
    [[ -n "$prompt_save" ]] && save="$prompt_save"
    [[ -n "$prompt_country" ]] && country="$prompt_country"
    [[ -n "$prompt_protocols" ]] && protocols="$prompt_protocols"
}

echo
read -p "Do you want to manually set the LATEST and FASTEST values? (y/n): " prompt_choice
case "$prompt_choice" in
    [yY]*) prompt_user ;;
    [nN]*) ;;
esac

clear

# Reflector command with configurable options
reflector --age "$age" \
          --country "$country" \
          --fastest "$fastest" \
          --download-timeout "$timeout" \
          --latest "$latest" \
          --protocol "$protocols" \
          --save "$save" \
          --sort rate \
          --verbose
