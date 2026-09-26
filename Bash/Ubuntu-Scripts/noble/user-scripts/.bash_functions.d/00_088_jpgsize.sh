#!/usr/bin/env bash

jpgsize() {
    local random_dir size

    random_dir=$(mktemp -d)
    read -r -p "Enter the image size (units in MB): " size
    find . -size +"$size"M -type f -iname "*.jpg" > "$random_dir/img-sizes.txt"
    sed -i "s/^..//g" "$random_dir/img-sizes.txt"
    sed -i "s|^|$PWD\/|g" "$random_dir/img-sizes.txt"
    echo
    nohup gnome-text-editor "$random_dir/img-sizes.txt" &>/dev/null &
}
