#!/usr/bin/env bash

clear

box_out_banner() {
    input_char=$(echo "${@}" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=$line//-/ 
    echo " $line"
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "${@}"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner "YOUR MESSAGE HERE"
