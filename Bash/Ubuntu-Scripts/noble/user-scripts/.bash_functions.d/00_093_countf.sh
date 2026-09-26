#!/usr/bin/env bash

# COUNT ITEMS IN THE CURRENT FOLDER W/O SUBDIRECTORIES INCLUDED
countf() {
    local folder_count
    clear
    folder_count=$(find . -mindepth 1 -maxdepth 1 -printf . | wc -c)
    echo "There are $folder_count files in this folder"
}
