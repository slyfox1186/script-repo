#!/usr/bin/env bash

# Define the directory to search in and the pattern for file names
search_directory="/c/Users/jholl/OneDrive/Documents/GitHub/script-repo/Bash"

if [[ -z "$search_directory" ]]; then
    read -p "Enter the directory to search: " search_directory
    clear
fi

scripts=(minimize_comments.pl fix_function_braces.pl replace-variables-curly-brackets.pl)

for file in ${scripts[@]}; do
    # Path to your Perl script
    perl_script_path="$file"
    # Check if the Perl script exists
    if [[ ! -f "$perl_script_path" ]]; then
        echo "Perl script not found at: $perl_script_path"
    else
        # Use find to locate files and execute the Perl script on each
        find "$search_directory" -type f -exec perl "$perl_script_path" {} \;
    fi
    echo
done

if [[ "$?" -eq 0 ]]; then
    echo "Processed all matching files in $search_directory."
fi
