#!/usr/bin/env bash

clear

function box_out_banner()
{
    input_char=$(echo "${@}" | wc -c)
    line=$(for i in `seq 0 ${input_char}`; do printf "-"; done)
    tput bold
    line="$(tput setaf 3)${line}"
    space=${line//-/ }
    echo " ${line}"
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "${@}"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    echo " ${line}"
    tput sgr 0
}

box_out_banner 'Debian Package Downloader'

if [ -z "${1}" ]; then
    printf "\n%s\n\n%s\n\n%s\n\n" \
        'This script will download debian packages to the current directory.' \
        'To download, enter a space separated list of APT packages' \
        'Example: aptitude curl gedit gedit-plugins synaptic'
    read -p 'Enter your list here: ' pkgs
    
else
    pkgs="${1}"
fi

for i in ${pkgs[@]}
do
    printf "\n%s\n" 'Downloading...'
    wget -cq "$(apt-get install --reinstall --print-uris -qq ${i} 2>/dev/null | cut -d"'" -f2)"
done

printf "\n%s\n\n" 'The script has finished.'
