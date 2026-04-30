#!/usr/bin/env bash
# File System Utilities

## FIND COMMANDS ##
# SAFER FIND COMMAND - no eval to prevent command injection
ffind() {
    local fname="$1" ftype="$2" fpath="$3"
    local -a find_args

    # Check if any argument is passed
    if [[ "$#" -eq 0 ]]; then
        read -p "Enter the name to search for: " fname
        read -p "Enter a type of FILE (d|f|blank for any): " ftype
        read -p "Enter the starting path (blank for current directory): " fpath
    fi

    # Default to the current directory if fpath is empty
    fpath=${fpath:-.}

    # Build find command arguments safely
    find_args=("$fpath" -iname "$fname")
    
    if [[ -n $ftype ]]; then
        if [[ "$ftype" == "d" || "$ftype" == "f" ]]; then
            find_args+=(-type "$ftype")
        else
            echo "Invalid FILE type. Please use \"d\" for directories or \"f\" for files."
            return 1
        fi
    fi

    # Execute the command safely without eval
    find "${find_args[@]}"
}

## CREATE FILES ##
mf() {
    local file

    if [[ -z "$1" ]]; then
        read -p "Enter filename: " file
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
        read -p "Enter directory name: " dir
        mkdir -p "$PWD/$dir"
        cd "$PWD/$dir" || return 1
    else
        mkdir -p "$1"
        cd "$PWD/$1" || return 1
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

# RM COMMANDS ##

# Remove directory (optimized version - combines the duplicate functions)
rmd() {
    local dir
    if [[ -z "$*" ]]; then
        clear
        ls -1AvhF --color --group-directories-first
        echo
        read -p "Enter the directory path(s) to delete: " dir
    else
        dir=$*
    fi
    sudo rm -fr "$dir"
    echo
    ls -1AvhF --color --group-directories-first
}

# Remove file
rmf() {
    local files
    if [[ -z "$*" ]]; then
        clear
        ls -1AvhF --color --group-directories-first
        echo
        read -p "Enter the FILE path(s) to delete: " files
    else
        files=$*
    fi
    sudo rm "$files"
    echo
    ls -1AvhF --color --group-directories-first
}

## TAKE OWNERSHIP COMMANDS

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

## FIX USER FOLDER PERMISSIONS up = user permissions
fix_up() {
    sudo find "$HOME/.gnupg" -type f -exec chmod 600 {} \;
    sudo find "$HOME/.gnupg" -type d -exec chmod 700 {} \;
    sudo find "$HOME/.ssh" -type d -exec chmod 700 {} \;
    sudo find "$HOME/.ssh/id_rsa.pub" -type f -exec chmod 644 {} \;
    sudo find "$HOME/.ssh/id_rsa" -type f -exec chmod 600 {} \;
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
    folder_count=$(ls -1 | wc -l)
    echo "There are $folder_count files in this folder"
}

## Refresh thumbnail cache
rftn() {
    sudo rm -fr "$HOME/.cache/thumbnails"*
    sudo file "$HOME/.cache/thumbnails"
}

# Get system space specs
fs_info() {
    # Default values
    local show_inode=0
    local specific_dir=""
    local threshold=80
    local show_summary=0

    # Parse options
    local OPTIND
    while getopts "id:t:s" opt; do
        case $opt in
            i) show_inode=1 ;;
            d) specific_dir="$OPTARG" ;;
            t) threshold="$OPTARG" ;;
            s) show_summary=1 ;;
            *)
                echo "Usage: fs_info [-i] [-d directory] [-t threshold] [-s]"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))
    
    # Validate the directory argument to ensure it isn't another option
    if [[ -n "$specific_dir" && "$specific_dir" == -* ]]; then
        echo "Error: The -d option requires a valid directory argument, not '$specific_dir'."
        return 1
    fi

    # Optionally display disk usage for a specific directory,
    # suppressing errors (e.g. Permission denied)
    if [[ -n "$specific_dir" ]]; then
         echo -e "\nDisk usage for directory: $specific_dir"
         du -sh "$specific_dir" 2>/dev/null
    fi

    # Display file system usage (human-readable) using process substitution
    echo -e "\nFilesystem usage:"
    echo -e "Filesystem\tSize\tUsed\tAvail\tUse%\tMounted on"
    while read -r source size used avail pcent mount; do
         # Remove the '%' sign for numeric comparison
         usage=${pcent%\%}
         if [ "$usage" -ge "$threshold" ]; then
             color="\033[0;31m"  # Red if usage is at or above threshold
         else
             color="\033[0;32m"  # Green if below threshold
         fi
         echo -e "$source\t$size\t$used\t$avail\t${color}${pcent}\033[0m\t$mount"
    done < <(df -h --output=source,size,used,avail,pcent,target | tail -n +2)

    # Optionally display inode usage if the -i flag is provided
    if [ "$show_inode" -eq 1 ]; then
         echo -e "\nInode usage:"
         echo -e "Filesystem\tInodes\tIUsed\tIFree\tIUse%\tMounted on"
         while read -r source inodes iused ifree pcent mount; do
              usage=${pcent%\%}
              if [ "$usage" -ge "$threshold" ]; then
                  color="\033[0;31m"
              else
                  color="\033[0;32m"
              fi
              echo -e "$source\t$inodes\t$iused\t$ifree\t${color}${pcent}\033[0m\t$mount"
         done < <(df -ih --output=source,inodes,iused,ifree,pcent,target | tail -n +2)
    fi

    # Optionally display an overall summary if the -s flag is used
    if [ "$show_summary" -eq 1 ]; then
         echo -e "\nOverall summary:"
         df -h --total | tail -n 1
    fi
}

# Display files in a directory with various sort options
ls_interactive() {
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

  read -p "Enter your choice (1-6): " choice

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

# Define this function in your ~/.bashrc (or source it from a script file)

copy_this() {
  local src dest
  local -a INCLUDE=() EXCLUDE=()
  local DRY_RUN=false QUIET=false
  local script_dir

  # Determine the directory where this function was defined (i.e. the script/rc file)
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  src="$script_dir"   # default source

  # Usage helper
  _ce_usage() {
    cat <<EOF
Usage: copy_this -d <dest> [options]

Defaults to copying from the directory where this function lives:
  Source → $src

Required:
  -d <dir>        Destination directory

Options:
  -i <pattern>    Include only these patterns (repeatable)
  -e <pattern>    Exclude these patterns (repeatable)
  -n              Dry-run (show what would happen)
  -q              Quiet (no rsync -v)
  -h              Show this help and exit

Examples:
  # Copy only .sh from this script's dir into 'out/', excluding nothing:
  copy_this -i '*.sh' -d out/

  # Copy everything except .py:
  copy_this -e '*.py' -d out/

  # Dry-run: include .txt, exclude .log
  copy_this -i '*.txt' -e '*.log' -d out/ -n
EOF
  }

  # Parse args
  while [[ $# -gt 0 ]]; do
    case $1 in
      -i|--include)
        INCLUDE+=("$2"); shift 2 ;;
      -e|--exclude)
        EXCLUDE+=("$2"); shift 2 ;;
      -d|--dest|--destination)
        dest="$2"; shift 2 ;;
      -n|--dry-run)
        DRY_RUN=true; shift ;;
      -q|--quiet)
        QUIET=true; shift ;;
      -h|--help)
        _ce_usage; return 0 ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        _ce_usage; return 1 ;;
    esac
  done

  # Check required
  if [[ -z "${dest:-}" ]]; then
    echo "Error: -d <dest> is required." >&2
    _ce_usage; return 1
  fi

  # Ensure rsync is available
  if ! command -v rsync &>/dev/null; then
    echo "Error: rsync not found in PATH." >&2
    return 1
  fi

  # Build rsync command
  local cmd=(rsync -a)
  $QUIET || cmd+=(-v)
  $DRY_RUN && cmd+=(--dry-run)

  if (( ${#INCLUDE[@]} )); then
    cmd+=(--include='*/')
    for p in "${INCLUDE[@]}"; do cmd+=(--include="$p"); done
    for p in "${EXCLUDE[@]}"; do cmd+=(--exclude="$p"); done
    cmd+=(--exclude='*')
  else
    for p in "${EXCLUDE[@]}"; do cmd+=(--exclude="$p"); done
  fi

  cmd+=("$src"/ "$dest"/)

  echo "Running: ${cmd[*]}"
  "${cmd[@]}"
}

count_lines() {
    if [[ -z "$1" ]]; then
        echo "Usage: count_lines \"<filename>\""
        return 1
    fi

    local FILENAME
    FILENAME="$1"
    
    find ./ -type f -name "$FILENAME" -exec wc -l {} + 2>/dev/null |
    grep -v total |
    sort -nr |
    awk '{sub(/^\.\//, "", $2); print NR ". " $2 ": " $1 " lines"}'
}

count_chars() {
    if [[ -z "$1" ]]; then
        echo "Usage: count_chars \"<filename>\""
        return 1
    fi

    local FILENAME
    FILENAME="$1"

    find ./ -type f -name "$FILENAME" -exec wc -m {} + 2>/dev/null |
    grep -v total |
    sort -nr |
    awk '{sub(/^\.\//, "", $2); print NR ". " $2 ": " $1 " chars"}'
}
