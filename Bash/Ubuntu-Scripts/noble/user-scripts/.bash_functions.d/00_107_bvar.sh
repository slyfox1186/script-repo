#!/usr/bin/env bash

####################
## REGEX COMMANDS ##
####################

bvar() {
    local choice fname fname_tmp
    clear

    if [[ -z "$1" ]]; then
        read -r -p "Please enter the file path: " fname
        fname_tmp="$fname"
    else
        fname="$1"
        fname_tmp="$fname"
    fi

    if [[ -f "$fname" ]]; then
        fname+=".txt"
        mv "${fname_tmp}" "$fname"
    fi

    sed -e "s/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g" -e "s/\(\$\)\({}\)/\1/g" -e "s/\(\$\)\({}\)\({\)/\1\3/g" "$fname"

    printf "%s\n\n%s\n%s\n\n" \
        "Do you want to permanently change this file?" \
        "[1] Yes" \
        "[2] Exit"
    read -r -p "Your choices are ( 1 or 2): " choice
    clear
    case "$choice" in
        1)
                sed -i -e "s/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g" -i -e "s/\(\$\)\({}\)/\1/g" -i -e "s/\(\$\)\({}\)\({\)/\1\3/g" "$fname"
                mv "$fname" "${fname_tmp}"
                clear
                cat < "${fname_tmp}"
                ;;
        2)
                mv "$fname" "${fname_tmp}"
                return 0
                ;;
        *)
                unset choice
                bvar "${fname_tmp}"
                ;;
    esac
}
