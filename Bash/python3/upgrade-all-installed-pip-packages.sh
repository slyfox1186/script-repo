#!/usr/bin/env bash

clear

list_pkgs="$(pip list | awk '{print $1}')"

for p in ${list_pkgs[@]}
do
    pip install --upgrade $p
    echo
done
