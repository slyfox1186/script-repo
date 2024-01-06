#!/usr/bin/env bash

clear

list_pkgs="$(pip list | awk '{print $1}')"

for p in ${list_pkgs[@]}
do
    if [ $p != wxPython ]; then
        pip install --user --upgrade pip
        pip install --user --upgrade $p
    fi
    echo
done
