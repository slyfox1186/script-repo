#!/usr/bin/env bash

# Define foreground color codes
FG_COLORS=(
    "30"  # Black
    "31"  # Red
    "32"  # Green
    "33"  # Yellow
    "34"  # Blue
    "35"  # Magenta
    "36"  # Cyan
    "37"  # White
    "90"  # Light Black
    "91"  # Light Red
    "92"  # Light Green
    "93"  # Light Yellow
    "94"  # Light Blue
    "95"  # Light Magenta
    "96"  # Light Cyan
    "97"  # Light White
)

# Define background color codes
BG_COLORS=(
    "40"  # Black (native)
    "41"  # Red
    "42"  # Green
    "43"  # Yellow
    "44"  # Blue
    "45"  # Magenta
    "46"  # Cyan
    "47"  # White
    "100" # Light Black
    "101" # Light Red
    "102" # Light Green
    "103" # Light Yellow
    "104" # Light Blue
    "105" # Light Magenta
    "106" # Light Cyan
    "107" # Light White
)

# Function to display color combinations
display_color_combinations() {
    local fg_code="$1"
    local bg_code="$2"
    echo -e "\033[${fg_code};${bg_code}mForeground ${fg_code}, Background ${bg_code}\033[0m"
}

# Function to display help menu
display_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo "Options:"
    echo "  -h, --help          Display this help menu"
    echo "  -f, --foreground    Specify the foreground color code (30-37, 90-97)"
    echo "  -b, --background    Specify the background color code (40-47, 100-107)"
    exit 0
}

# Check if help option is passed
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    display_help
fi

# Check if arguments are provided
if [ "$#" -eq 4 ]; then
    if [[ "$1" == "-f" || "$1" == "--foreground" ]] && [[ "$3" == "-b" || "$3" == "--background" ]]; then
        fg_arg="$2"
        bg_arg="$4"
        
        # Validate foreground and background color arguments
        if [[ " ${FG_COLORS[*]} " == *" $fg_arg "* ]] && [[ " ${BG_COLORS[*]} " == *" $bg_arg "* ]]; then
            display_color_combinations "$fg_arg" "$bg_arg"
        else
            echo "Invalid foreground or background color."
            exit 1
        fi
    else
        echo "Invalid arguments. Use -h or --help for usage information."
        exit 1
    fi
else
    # Prompt user for choice if no arguments are provided
    echo "Choose display mode:"
    echo
    echo "1. Native background color"
    echo "2. Non-native background colors"
    echo
    read -p "Enter your choice (1 or 2): " choice
    clear

    # Validate user input
    if [[ $choice == "1" ]]; then
        # Loop through each foreground color with native background color
        for fg_color_code in "${FG_COLORS[@]}"; do
            # Print with native background color
            display_color_combinations "$fg_color_code" "40"
        done
    elif [[ $choice == "2" ]]; then
        # Loop through each foreground color with non-native background colors
        for fg_color_code in "${FG_COLORS[@]}"; do
            # Loop through each background color
            for bg_color_code in "${BG_COLORS[@]}"; do
                # Print colored text
                display_color_combinations "$fg_color_code" "$bg_color_code"
            done
            echo  # Add a blank line between each foreground color
        done
    else
        echo "Invalid choice. Please enter either 1 or 2."
        exit 1
    fi
fi
