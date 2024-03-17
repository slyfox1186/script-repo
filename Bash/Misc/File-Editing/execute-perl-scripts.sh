#!/usr/bin/env bash

search_directory="/c/Users/jholl/OneDrive/Documents/GitHub/script-repo/Bash"

if [[ -z "$search_directory" ]]; then
    read -p "Enter the directory to search: " search_directory
    clear
fi

scripts=(minimize_comments.pl fix_function_braces.pl replace-variables-curly-brackets.pl)

for file in ${scripts[@]}; do
    perl_script_path="$file"
    if [[ ! -f "$perl_script_path" ]]; then
        echo "Perl script not found at: $perl_script_path"
    else
        find "$search_directory" -type f -exec perl "$perl_script_path" {} \;
    fi
    echo
done

if [[ "$?" -eq 0 ]]; then
    echo "Processed all matching files in $search_directory."
fi
