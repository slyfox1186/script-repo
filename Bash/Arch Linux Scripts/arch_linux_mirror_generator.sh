#!/bin/bash

# Output file name
output_file="mirror-results.txt"
temp_file="temp.txt"

# URL to fetch the mirror list from
url="https://archlinux.org/mirrorlist/?ip_version=6"

# Country codes
declare -A country_codes=(
    ["Australia"]="AU"
    ["Austria"]="AT"
    ["Bangladesh"]="BD"
    ["Belarus"]="BY"
    ["Belgium"]="BE"
    ["Bosnia-and-Herzegovina"]="BA"
    ["Brazil"]="BR"
    ["Bulgaria"]="BG"
    ["Cambodia"]="KH"
    ["Canada"]="CA"
    ["Chile"]="CL"
    ["China"]="CN"
    ["Colombia"]="CO"
    ["Czechia"]="CZ"
    ["Denmark"]="DK"
    ["Ecuador"]="EC"
    ["Estonia"]="EE"
    ["Finland"]="FI"
    ["France"]="FR"
    ["Germany"]="DE"
    ["Greece"]="GR"
    ["Hong-Kong"]="HK"
    ["Iceland"]="IS"
    ["India"]="IN"
    ["Indonesia"]="ID"
    ["Iran"]="IR"
    ["Israel"]="IL"
    ["Italy"]="IT"
    ["Japan"]="JP"
    ["Kazakhstan"]="KZ"
    ["Kenya"]="KE"
    ["Latvia"]="LV"
    ["Luxembourg"]="LU"
    ["Mauritius"]="MU"
    ["Mexico"]="MX"
    ["Moldova"]="MD"
    ["Netherlands"]="NL"
    ["New-Caledonia"]="NC"
    ["New-Zealand"]="NZ"
    ["North-Macedonia"]="MK"
    ["Norway"]="NO"
    ["Paraguay"]="PY"
    ["Poland"]="PL"
    ["Portugal"]="PT"
    ["Romania"]="RO"
    ["Russia"]="RU"
    ["Serbia"]="RS"
    ["Singapore"]="SG"
    ["Slovakia"]="SK"
    ["South-Africa"]="ZA"
    ["South-Korea"]="KR"
    ["Spain"]="ES"
    ["Sweden"]="SE"
    ["Switzerland"]="CH"
    ["Taiwan"]="TW"
    ["Thailand"]="TH"
    ["Turkey"]="TR"
    ["Ukraine"]="UA"
    ["United-Kingdom"]="GB"
    ["United-States"]="US"
)

# Function to display the help menu
display_help() {
    echo
    echo "Usage: $0 [OPTIONS] [COUNTRY_KEYS]"
    echo
    echo "Generates a custom mirror list based on the specified countries."
    echo
    echo "Options:"
    echo "  -h, --help      Display this help menu"
    echo "  -l, --list      List all available country keys"
    echo
    echo "Example:"
    echo "  $0 US CA GB"
}

# Function to list all country keys
list_country_keys() {
    echo
    echo "Available Country Keys:"
    echo "+-------------------------------------+---------------+"
    echo "| Country                             | Abbreviation  |"
    echo "+-------------------------------------+---------------+"
    # Sort the country codes array by key
    for country in "${!country_codes[@]}"; do
        sorted_countries+=("$country")
    done
    IFS=$'\n' sorted_countries=($(sort <<<"${sorted_countries[*]}"))
    unset IFS

    # Print the sorted country keys and abbreviations
    for country in "${sorted_countries[@]}"; do
        abbreviation="${country_codes[$country]}"
        printf "| %-35s | %-13s |\n" "$country" "$abbreviation"
    done
    echo "+-------------------------------------+---------------+"
}

# Download the mirror list using curl and save it to a temporary file
curl -s "$url" > "$temp_file"

# Check if the list countries option is provided
if [[ "$1" == "-l" || "$1" == "--list" ]]; then
    list_country_keys
    exit 0
fi

# Check if the help option is provided
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    display_help
    exit 0
fi

# Clear the output file
echo -n "" > "$output_file"

# Extract the date from the downloaded file
generated_date=$(grep -oP '## Generated on \K\d{4}-\d{2}-\d{2}' "$temp_file")

# Write the comments at the top of the output file
echo "##" >> "$output_file"
echo "## Arch Linux repository mirrorlist" >> "$output_file"
echo "## Generated on $generated_date" >> "$output_file"
echo "##" >> "$output_file"
echo "" >> "$output_file"

# Flag to track if inside a desired country section
inside_desired_country=false

# Temporary file to store the filtered lines
filtered_file="filtered.txt"

# Read the downloaded file line by line
while IFS= read -r line; do
    # Check if the line starts with "##" indicating a country section
    if [[ $line == \#\#* ]]; then
        # Extract the country name from the line
        country=$(echo "$line" | sed 's/## //' | sed 's/ /-/g')
        country_key="${country_codes[$country]}"

        # Check if the country key is in the list of desired countries
        if [[ " ${@^^} " =~ " $country_key " ]]; then
            inside_desired_country=true
            echo "$line" >> "$filtered_file"
        else
            inside_desired_country=false
        fi
    fi

    # If inside a desired country section, write the line to the filtered file
    if $inside_desired_country; then
        echo "$line" >> "$filtered_file"
    fi
done < "$temp_file"

# Remove duplicate lines from the filtered file and append to the output file
uniq "$filtered_file" >> "$output_file"

# Remove the temporary files
rm "$temp_file"
rm "$filtered_file"

echo "Output file '$output_file' created successfully."
