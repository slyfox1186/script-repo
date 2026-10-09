#!/usr/bin/env bash
# File System Functions

# CREATE GLOBAL FUNCTIONS

# cd wrapper: record every directory change on the stack (pushd) so that
# `cd..` (popd) walks back to the previous folder you were in.
cd() {
    case "${1-}" in
        "") builtin pushd "$HOME" > /dev/null || return ;;    # bare `cd` -> home
        -) builtin pushd "$OLDPWD" > /dev/null || return ;;   # `cd -` -> previous dir
        *) builtin pushd "$@" > /dev/null || return ;;        # normal `cd <dir>`
    esac
}

## FIND COMMANDS ##
ffind() {
    local fname="${1-}" ftype="${2-}" fpath="${3-}"
    local -a find_args

    # Check if any argument is passed
    if [[ "$#" -eq 0 ]]; then
        read -r -p "Enter the name to search for: " fname
        read -r -p "Enter a type of FILE (d|f|blank for any): " ftype
        read -r -p "Enter the starting path (blank for current directory): " fpath
    fi

    # Default to the current directory if fpath is empty
    fpath=${fpath:-.}

    find_args=("$fpath" -iname "$fname")
    if [[ -n "$ftype" ]]; then
        case "$ftype" in
            d|f) find_args+=(-type "$ftype") ;;
            *)
            echo "Invalid FILE type. Please use \"d\" for directories or \"f\" for files."
            return 1
            ;;
        esac
    fi

    command find "${find_args[@]}"
}

## CREATE FILES ##
mf() {
    local file

    if [[ -z "$1" ]]; then
        read -r -p "Enter filename: " file
        [[ ! -f "$file" ]] && touch "$file"
        chmod 744 "$file"
    else
        [[ ! -f "$1" ]] && touch "$1"
        chmod 744 "$1"
    fi

    clear; ls -1AhFv --color --group-directories-first
}

mdir() {
    local dir

    if [[ -z "$1" ]]; then
        read -r -p "Enter directory name: " dir
        mkdir -p "$PWD/$dir"
        cd "$PWD/$dir" || exit 1
    else
        mkdir -p "$1"
        cd "$PWD/$1" || exit 1
    fi

    clear; ls -1AhFv --color --group-directories-first
}

# Copy file
cpf() {
    [[ ! -d "$HOME/tmp" ]] && mkdir -p "$HOME/tmp"
    cp "$1" "$HOME/tmp/$1"
    chown -R "$USER:$USER" "$HOME/tmp/$1"
    chmod -R 744 "$HOME/tmp/$1"
    clear
    ls -1AhFv --color --group-directories-first
}

# Move file
mvf() {
    [[ ! -d "$HOME/tmp" ]] && mkdir -p "$HOME/tmp"
    mv "$1" "$HOME/tmp/$1"
    chown -R "$USER:$USER" "$HOME/tmp/$1"
    chmod -R 744 "$HOME/tmp/$1"
    clear
    ls -1AhFv --color --group-directories-first
}

# TAKE OWNERSHIP COMMANDS

toa() {
    sudo chown -R "$USER":"$USER" "$PWD"
    sudo chmod -R 744 "$PWD"
    clear; ls -1AvhF --color --group-directories-first
}

town() {
    local files
    files=("$@")

    for file in "${files[@]}"; do
        if [[ -e "$file" ]]; then
            if sudo chmod 755 "$file" && sudo chown "$USER":"$USER" "$file"; then
                clear
                ls -1AvhF --color --group-directories-first
            else
                clear
                echo "Failed to change ownership and permissions of: $file"
                return 1
            fi
        else
            clear
            echo "File does not exist: $file"
            return 1
        fi
    done
}

rmd() {
    local path resolved_path
    local -a dirs

    if (($# == 0)); then
        clear
        ls -1AvhF --color --group-directories-first
        echo
        read -r -a dirs -p "Enter the directory path(s) to delete: "
    else
        dirs=("$@")
    fi

    ((${#dirs[@]} > 0)) || return 1
    for path in "${dirs[@]}"; do
        [[ -n "$path" ]] || {
            printf 'Refusing an empty directory target.\n' >&2
            return 1
        }
        resolved_path=$(realpath -m -- "$path") || return 1
        case "$resolved_path" in
            /|"$HOME")
                printf 'Refusing unsafe directory target: %q\n' "$path" >&2
                return 1
                ;;
        esac
    done

    sudo rm -rf -- "${dirs[@]}"
    echo
    ls -1AvhF --color --group-directories-first
}

rmf() {
    local -a files

    if (($# == 0)); then
        clear
        ls -1AvhF --color --group-directories-first
        echo
        read -r -a files -p "Enter the file path(s) to delete: "
    else
        files=("$@")
    fi

    ((${#files[@]} > 0)) || return 1
    sudo rm -- "${files[@]}"
    echo
    ls -1AvhF --color --group-directories-first
}

## Count files in the directory
count_dir() {
    local keep_count
    keep_count=$(find . -maxdepth 1 -type f | wc -l)
    echo "The total directory file count is (non-recursive): $keep_count"
    echo
}

count_dirr() {
    local keep_count
    clear
    keep_count=$(find . -type f | wc -l)
    echo "The total directory file count is (recursive): $keep_count"
    echo
}

# COUNT ITEMS IN THE CURRENT FOLDER W/O SUBDIRECTORIES INCLUDED
countf() {
    local folder_count
    clear
    folder_count=$(find . -mindepth 1 -maxdepth 1 -printf . | wc -c)
    echo "There are $folder_count files in this folder"
}

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

dfl() {
  if [ -z "$1" ]; then
    echo "Please provide the full path of a folder as an argument."
    return 1
  fi

  if [ ! -d "$1" ]; then
    echo "The provided path is not a valid directory."
    return 1
  fi

  echo "How do you want to display the files?"
  echo "1. By name"
  echo "2. By date installed"
  echo "3. By date modified"
  echo "4. By date accessed"
  echo "5. By date created"
  echo "6. By size"

  read -r -p "Enter your choice (1-6): " choice

  case $choice in
    1)
      ls -1 "$1"
      ;;
    2)
      ls -1tr "$1"
      ;;
    3)
      ls -1t "$1"
      ;;
    4)
      ls -1u "$1"
      ;;
    5)
      ls -1U "$1"
      ;;
    6)
      ls -1S "$1"
      ;;
    *)
      echo "Invalid choice. Please enter a number between 1 and 6."
      ;;
  esac
}
