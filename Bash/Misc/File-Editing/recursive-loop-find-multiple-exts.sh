#!/usr/bin/env bash

ext_1="bat"
ext_2="sh"

prompt_user() {
    echo "Include the parent folder?"
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choices are (1 or 2): " choice
    clear
    
    case "$choice" in
        1) store_paths="$(find . -type f \( -iname \*.$ext_1 -o -iname \*.$ext_2 \) -exec bash -c "echo {} | sed -E 's/.*\s(.*)/\1/'" \;)" ;;
        2) store_paths="$(find . -mindepth 2 -type f \( -iname \*.$ext_1 -o -iname \*.$ext_2 \) -exec bash -c "echo {} | sed -E 's/.*\s(.*)/\1/'" \;)" ;;
        *) unset choice
           clear
           prompt_user
           ;;
    esac
}

for i in ${store_paths[@]}; do
    echo "$PWD/${i:2}"
done
