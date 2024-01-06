#!/usr/bin/env bash

clear

list_pkgs="$(pip list | awk '{print $1}')"

pip install --user --upgrade pip

for p in ${list_pkgs[@]}
do
    if [ $p != wxPython ]; then
        pip install --user --upgrade $p
    fi
    echo
done
