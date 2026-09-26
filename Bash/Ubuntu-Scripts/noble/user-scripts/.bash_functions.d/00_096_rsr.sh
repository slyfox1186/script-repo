#!/usr/bin/env bash

####################
## RSYNC COMMANDS ##
####################

rsr() {
    local destination source modified_source

    # you must add an extra folder that is a period "/./" between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the source folder instead of the source
    # folder and its subfiles only.

    echo "This rsync command will recursively copy the source folder to the chosen destination."
    echo "The original files will still be located in the source folder."
    echo "If you want to move the files (which deletes the originals then use the function 'rsrd'."
    echo "Please enter the full paths of the source and destination directories."
    echo

    read -r -p "Enter the source path: " source
    read -r -p "Enter the destination path: " destination
    source=$(realpath -m -- "$source")
    modified_source="${source%/*}/./${source##*/}"
    echo

    rsync -aqvR --acls --perms --mkpath --info=progress2 "$modified_source" "$destination"
}
