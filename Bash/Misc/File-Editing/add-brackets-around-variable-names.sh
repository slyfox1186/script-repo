#!/usr/bin/env bash

# SCRIPT PURPOSE: PUT BRACKETS AROUND VARIABLES: $SOME_NAME >> $SOME_NAME

if [ "$EUID" -eq '0' ]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# ENTER THE PATH TO THE FILE
fname=a.txt

sed -e 's/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g' "$fname"

printf "%s\n\n%s\n%s\n\n"                          \
    'Do you want to permanently change this file?' \
    '[1] Yes'                                      \
    '[2] Exit'
read -p 'Your choices are ( 1 or 2): ' choice
clear

case "$choice" in
    1)
            sed -i 's/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g' "$fname"
            clear
            cat < "$fname"
            printf "%s\n\n" 'The new file is show above!'
            ;;
    2)      exit 0;;
esac
