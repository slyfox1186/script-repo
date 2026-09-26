#!/usr/bin/env bash

rsrd() {
    local destination source modified_source

    # you must add an extra folder that is a period "/./" between the full path to the source folder and the source folder itself
    # or rsync will copy the files to the destination directory and it will be the full path of the souce folder instead of the source
    # folder and its subfiles only.

    echo "This rsync command will recursively copy the source folder to the chosen destination."
    echo "The original files will be DELETED after they have been copied to the destination."
    echo "If you want to move the files (which deletes the originals then use the function 'rsrd'."
    echo "Please enter the full paths of the source and destination directories."
    echo

    read -r -p "Enter the source path: " source
    read -r -p "Enter the destination path: " destination
    source=$(realpath -m -- "$source")
    modified_source="${source%/*}/./${source##*/}"
    echo

    rsync -aqvR --acls --perms --mkpath --remove-source-files "$modified_source" "$destination"
}
