#!/usr/bin/env bash

# Define foreground color codes
FG_COLORS=(
    "30"   # Black
    "31"   # Red
    "32"   # Green
    "33"   # Yellow
    "34"   # Blue
    "35"   # Magenta
    "36"   # Cyan
    "37"   # White
    "90"   # Light Black
    "91"   # Light Red
    "92"   # Light Green
    "93"   # Light Yellow
    "94"   # Light Blue
    "95"   # Light Magenta
    "96"   # Light Cyan
    "97"   # Light White
    "1;30" # Bold Black
    "1;31" # Bold Red
    "1;32" # Bold Green
    "1;33" # Bold Yellow
    "1;34" # Bold Blue
    "1;35" # Bold Magenta
    "1;36" # Bold Cyan
    "1;37" # Bold White
    "1;90" # Bold Light Black
    "1;91" # Bold Light Red
    "1;92" # Bold Light Green
    "1;93" # Bold Light Yellow
    "1;94" # Bold Light Blue
    "1;95" # Bold Light Magenta
    "1;96" # Bold Light Cyan
    "1;97" # Bold Light White
)

# Define background color codes
BG_COLORS=(
    "40"   # Black (native)
    "41"   # Red
    "42"   # Green
    "43"   # Yellow
    "44"   # Blue
    "45"   # Magenta
    "46"   # Cyan
    "47"   # White
    "100"  # Light Black
    "101"  # Light Red
    "102"  # Light Green
    "103"  # Light Yellow
    "104"  # Light Blue
    "105"  # Light Magenta
    "106"  # Light Cyan
    "107"  # Light White
    "1;40"   # Bold Black (native)
    "1;41"   # Bold Red
    "1;42"   # Bold Green
    "1;43"   # Bold Yellow
    "1;44"   # Bold Blue
    "1;45"   # Bold Magenta
    "1;46"   # Bold Cyan
    "1;47"   # Bold White
    "1;100"  # Bold Light Black
    "1;101"  # Bold Light Red
    "1;102"  # Bold Light Green
    "1;103"  # Bold Light Yellow
    "1;104"  # Bold Light Blue
    "1;105"  # Bold Light Magenta
    "1;106"  # Bold Light Cyan
    "1;107"  # Bold Light White
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
    echo "  -f, --foreground    Specify the foreground color code (30-37, 90-97, 1;30-1;37)"
    echo "  -b, --background    Specify the background color code (40-47, 100-107, 1;40-1;47, 1;100-1;107)"
    exit 0
}

# Parse command-line arguments
while getopts ":hf:b:" opt; do
    case $opt in
        h)
            display_help
            ;;
        f)
            fg_arg="$OPTARG"
            ;;
        b)
            bg_arg="$OPTARG"
            ;;
        :)
            echo "Option -$OPTARG requires an argument."
            exit 1
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            exit 1
            ;;
    esac
done

# Check if help option is passed
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    display_help
fi

#!/usr/bin/env bash

# ... (rest of the script remains the same)

# Check if both foreground and background arguments are provided
if [[ -z $fg_arg ]] || [[ -z $bg_arg ]]; then
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
            echo "Type: STANDARD"
            # Loop through standard background colors
            for bg_color_code in "${BG_COLORS[@]::16}"; do
                # Print colored text
                display_color_combinations "$fg_color_code" "$bg_color_code"
            done
            echo
            echo "Type: BOLD"
            # Loop through bold background colors
            for bg_color_code in "${BG_COLORS[@]:16}"; do
                # Print colored text
                display_color_combinations "$fg_color_code" "$bg_color_code"
            done
            echo  # Add a blank line between each foreground color
        done
    else
        echo "Invalid choice. Please enter either 1 or 2."
        exit 1
    fi
else
    # Validate foreground and background color arguments
    if [[ " ${FG_COLORS[@]} " =~ " $fg_arg " ]] && [[ " ${BG_COLORS[@]} " =~ " $bg_arg " ]]; then
        display_color_combinations "$fg_arg" "$bg_arg"
    else
        echo "Invalid foreground or background color."
        exit 1
    fi
fi
