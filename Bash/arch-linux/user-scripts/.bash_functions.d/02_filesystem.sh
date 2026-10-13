#!/usr/bin/env bash
# File System Functions

# cd wrapper: every successful directory change is also recorded on the directory stack, so
# `dirs -v` lists where you have been and `popd` returns to the previous folder. Options such
# as -P, -L and -- reach the builtin unchanged.
cd() {
    builtin cd "$@" || return
    builtin pushd -n "$OLDPWD" > /dev/null
}

## FIND COMMANDS ##
ffind() {
    local fname="${1-}" ftype="${2-}" fpath="${3-}"
    local -a find_args

    if (($# == 0)); then
        read -r -p "Enter the name to search for: " fname
        read -r -p "Enter a type of FILE (d|f|blank for any): " ftype
        read -r -p "Enter the starting path (blank for current directory): " fpath
    fi
    if [[ -z "$fname" ]]; then
        echo "A name to search for is required."
        return 1
    fi
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
    local file="${1-}"

    if [[ -z "$file" ]]; then
        read -r -p "Enter filename: " file || return 1
    fi
    [[ -n "$file" ]] || return 1
    touch -- "$file" || return
    clear; ls -1AhFv --color --group-directories-first
}

mdir() {
    local dir="${1-}"

    if [[ -z "$dir" ]]; then
        read -r -p "Enter directory name: " dir || return 1
    fi
    [[ -n "$dir" ]] || return 1
    mkdir -p -- "$dir" && cd -- "$dir" || return
    clear; ls -1AhFv --color --group-directories-first
}

# Copy or move a file or folder into ~/tmp, keeping its name, ownership and permissions.
cpf() {
    (($# > 0)) || { printf 'Usage: cpf PATH...\n' >&2; return 1; }
    mkdir -p -- "$HOME/tmp" && cp -a -- "$@" "$HOME/tmp/" || return
    clear; ls -1AhFv --color --group-directories-first
}

mvf() {
    (($# > 0)) || { printf 'Usage: mvf PATH...\n' >&2; return 1; }
    mkdir -p -- "$HOME/tmp" && mv -- "$@" "$HOME/tmp/" || return
    clear; ls -1AhFv --color --group-directories-first
}

# Succeeds when PATH is /, $HOME, an ancestor of $HOME, or a top-level system directory.
_is_protected_path() {
    local path
    path=$(realpath -m -- "$1") || return 0
    case "$path" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/snap|/srv|/sys|/tmp|/usr|/usr/*|/var)
            return 0 ;;
    esac
    [[ "$HOME/" == "$path/"* ]]
}

# TAKE OWNERSHIP COMMANDS

# Take ownership of the current directory tree. Directories and files that are already
# executable stay traversable or runnable; plain files do not become executable.
toa() {
    local answer
    if _is_protected_path "$PWD"; then
        printf 'Refusing to change ownership of %s.\n' "$PWD" >&2
        return 1
    fi
    read -r -p "Take ownership of everything under $PWD? [y/N] " answer || return 1
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || return 1
    sudo chown -R -- "$USER:$USER" "$PWD" && sudo chmod -R u+rwX,go+rX -- "$PWD" || return
    clear; ls -1AvhF --color --group-directories-first
}

town() {
    local file

    (($# > 0)) || { printf 'Usage: town PATH...\n' >&2; return 1; }
    for file in "$@"; do
        if [[ ! -e "$file" ]]; then
            echo "File does not exist: $file"
            return 1
        fi
        if ! sudo chown -- "$USER:$USER" "$file" || ! sudo chmod 755 -- "$file"; then
            echo "Failed to change ownership and permissions of: $file"
            return 1
        fi
    done
    clear
    ls -1AvhF --color --group-directories-first
}

# Shows the targets and asks before deleting with sudo.
_confirm_delete() {
    local answer
    printf 'About to delete with sudo:\n'
    printf '  %s\n' "$@"
    read -r -p 'Delete these? [y/N] ' answer || return 1
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]]
}

rmd() {
    local path
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
        if [[ -z "$path" ]] || _is_protected_path "$path"; then
            printf 'Refusing unsafe directory target: %q\n' "$path" >&2
            return 1
        fi
    done
    _confirm_delete "${dirs[@]}" || return 1
    sudo rm -rf -- "${dirs[@]}" || return
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
    _confirm_delete "${files[@]}" || return 1
    sudo rm -- "${files[@]}" || return
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

# Count every item (files, folders, links) directly inside the current folder.
countf() {
    local item_count
    clear
    item_count=$(find . -mindepth 1 -maxdepth 1 -printf . | wc -c)
    echo "There are $item_count items in this folder"
}

####################
## RSYNC COMMANDS ##
####################

# rsync -R copies the path after "/./", so inserting it before the last component recreates
# only the source folder itself inside the destination, not its full absolute path.
_rsync_relative_source() {
    local source
    source=$(realpath -e -- "$1") || return
    printf '%s/./%s\n' "${source%/*}" "${source##*/}"
}

rsr() {
    local destination source modified_source

    echo "This rsync command recursively copies the source folder into the chosen destination."
    echo "The original files stay in the source folder. To move them instead, use 'rsrd'."
    echo
    read -r -p "Enter the source path: " source || return 1
    read -r -p "Enter the destination path: " destination || return 1
    modified_source=$(_rsync_relative_source "$source") || return
    echo

    rsync -aR --acls --mkpath --info=progress2 -- "$modified_source" "$destination"
}

rsrd() {
    local answer destination source modified_source

    echo "This rsync command recursively moves the source folder into the chosen destination."
    echo "Each source file is DELETED after it has been copied. To keep them, use 'rsr'."
    echo
    read -r -p "Enter the source path: " source || return 1
    read -r -p "Enter the destination path: " destination || return 1
    modified_source=$(_rsync_relative_source "$source") || return
    source=${modified_source/\/.\//\/}
    if _is_protected_path "$source"; then
        printf 'Refusing to move %s.\n' "$source" >&2
        return 1
    fi
    read -r -p "Move $source into $destination? [y/N] " answer || return 1
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || return 1
    echo

    rsync -aR --acls --mkpath --info=progress2 --remove-source-files -- "$modified_source" "$destination" || return
    # --remove-source-files leaves the emptied folder tree behind.
    find "$source" -depth -type d -empty -delete
}

dfl() {
    local choice

    if [[ -z "${1-}" ]]; then
        echo "Please provide the full path of a folder as an argument."
        return 1
    fi
    if [[ ! -d "$1" ]]; then
        echo "The provided path is not a valid directory."
        return 1
    fi

    echo "How do you want to display the files?"
    echo "1. By name"
    echo "2. By date modified, oldest first"
    echo "3. By date modified, newest first"
    echo "4. By date accessed, newest first"
    echo "5. By date created, newest first"
    echo "6. By size, largest first"

    read -r -p "Enter your choice (1-6): " choice

    case $choice in
        1) ls -1 -- "$1" ;;
        2) ls -1tr -- "$1" ;;
        3) ls -1t -- "$1" ;;
        4) ls -1tu -- "$1" ;;
        5) ls -1t --time=birth -- "$1" ;;
        6) ls -1S -- "$1" ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 6."
            return 1
            ;;
    esac
}
