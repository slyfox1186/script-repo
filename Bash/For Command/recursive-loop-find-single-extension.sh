#!/usr/bin/env bash

clear

fext=sh

printf "%s\n\n%s\n%s\n\n" \
    'Include the parent folder?' \
    '[1] Yes' \
    '[2] No'
read -p 'Your choices are (1 or 2): ' choice
clear

case "${choice}" in
    1)      store_paths="$(find . -type f -iname "*.$fext" -exec bash -c "echo {} | sed -E 's/.*\s(.*)/\1/'" \;)";;
    2)      store_paths="$(find . -mindepth 2 -type f -iname "*.$fext" -exec bash -c "echo {} | sed -E 's/.*\s(.*)/\1/'" \;)";;
    *)
            clear
            printf "%s\n\n" 'Bad user input.'
            exit 1
esac

for i in ${store_paths[@]}
do
    fpath="${i:2}"
    echo "$PWD/$fpath"
done

unset choice
