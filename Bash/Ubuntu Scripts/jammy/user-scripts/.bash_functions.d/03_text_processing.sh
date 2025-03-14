#!/bin/bash
# Text Processing Functions

## AWK COMMANDS ##

# Removed all duplicate lines: outputs to terminal
rmd_lines() {
    awk '!seen[$0]++' "$1"
}

# Remove consecutive duplicate lines: outputs to terminal
rmdc() {
    awk 'f!=$0{print;f=$0}' "$1"
}

# Remove all duplicate lines and removes trailing spaces before comparing: replaces the file
rmdl() {
    perl -i -lne "s/\s*$//; print if ! \$x{\$_}++" "$1"
    gnome-text-editor "$1"
}

## SED COMMANDS ##
fsed() {
    local otext rtext
    echo "This command is for sed to act only on files"
    echo

    if [[ -z "$1" ]]; then
        read -p "Enter the original text: " otext
        read -p "Enter the replacement text: " rtext
        echo
    else
        otext=$1
        rtext=$2
    fi

     sudo sed -i "s/${otext}/${rtext}/g" "$(find . -maxdepth 1 -type f)"
}

# REGEX COMMANDS
bvar() {
    local choice fext flag fname
    clear

    if [[ -z "$1" ]]; then
        read -p "Please enter the file path: " fname
        fname_tmp="$fname"
    else
        fname="$1"
        fname_tmp="$fname"
    fi

    fext="${fname#*.}"
    if [[ -f "$fname" ]]; then
        fname+=".txt"
        mv "${fname_tmp}" "$fname"
    fi

    cat < "$fname" | sed -e "s/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g" -e "s/\(\$\)\({}\)/\1/g" -e "s/\(\$\)\({}\)\({\)/\1\3/g"

    printf "%s\n\n%s\n%s\n\n" \
        "Do you want to permanently change this file?" \
        "[1] Yes" \
        "[2] Exit"
    read -p "Your choices are ( 1 or 2): " choice
    clear
    case "$choice" in
        1)
                sed -i -e "s/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g" -i -e "s/\(\$\)\({}\)/\1/g" -i -e "s/\(\$\)\({}\)\({\)/\1\3/g" "$fname"
                mv "$fname" "${fname_tmp}"
                clear
                cat < "${fname_tmp}"
                ;;
        2)
                mv "$fname" "${fname_tmp}"
                return 0
                ;;
        *)
                unset choice
                bvar "${fname_tmp}"
                ;;
    esac
}

rm_curly() {
    local content file transform_string
    # FUNCTION TO TRANSFORM THE STRING
    transform_string() {
        content=$(cat "$1")
        echo "${content//\$\{/\$}" | sed "s/\}//g"
    }

    # LOOP OVER EACH ARGUMENT
    for file in "$@"; do
        if [[ -f "$file" ]]; then
            # PERFORM THE TRANSFORMATION AND OVERWRITE THE FILE
            transform_string "$file" > "$file.tmp"
            mv "$file.tmp" "$file"
            echo "Modified file: $file"
        else
            echo "File not found: $file"
        fi
    done
}

# Install colordiff package
cdiff() {
    colordiff "$1" "$2"
}

# COPY ANY TEXT. DOES NOT NEED TO BE IN QUOTES
# EXAMPLE: ct This is so cool
# OUTPUT WHEN PASTED: This is so cool
# USAGE: cp <file name here>
cc() {
    local pipe
    if [[ -z "$*" ]]; then
        echo
        echo "The command syntax is shown below"
        echo "cc INPUT"
        echo "Example: cc $PWD"
        echo
        return 1
    else
        pipe=$@
    fi
    echo "$pipe" | xclip -i -rmlastnl -selection clipboard
}

# COPY A FILE"S FULL PATH
# USAGE: cp <file name here>
cfp() {
    local pipe
    if [[ -z "$*" ]]; then
        clear
        echo "The command syntax is shown below"
        echo "cfp INPUT"
        echo "Example: cfp $PWD"
        echo
        return 1
    else
        pipe=$@
    fi

    readlink -fn "$pipe" | xclip -i -selection clipboard
    clear
}

# COPY THE CONTENT OF A FILE
# USAGE: cf <file name here>
cfc() {
    local file
    clear

    if [[ -z "$1" ]]; then
        clear
        echo "The command syntax is shown below"
        echo "cfc INPUT"
        echo "Example: cfc $PWD"
        echo
        return 1
    else
        cat "$1" | xclip -i -rmlastnl -select clipboard
    fi
}

# Search for string in files
sst() {
  if [ -z "$1" ]; then
    echo "Usage: search_string \"<search string>\" [extensions separated by ';']"
    return 1
  fi

  local pattern="$1"
  shift  # Remove the first argument so $1 now represents the extension list (if provided)
  
  # Prepare an array with basic grep options
  local args=( "-r" "-n" "--color=auto" )

  # If extensions are provided, add a --include flag for each one
  if [ -n "$1" ]; then
    IFS=';' read -ra exts <<< "$1"
    for ext in "${exts[@]}"; do
      args+=( "--include=*.$ext" )
    done
  fi
  
  # Append the search pattern and current directory to the arguments
  args+=( "$pattern" "." )

  # Execute grep with the constructed options
  grep "${args[@]}"
}

# BATCAT COMMANDS
bat() {
    if command -v batcat &>/dev/null; then
        eval "$(command -v batcat)" "$@"
    elif command -v bat &>/dev/null; then
        eval "$(command -v bat)" "$@"
    else
        echo "Installing batcat now."
        sudo apt update
        sudo apt -y install bat
    fi
}

batn() {
    if command -v batcat &>/dev/null; then
        eval "$(command -v batcat)" -n "$@"
    elif command -v bat &>/dev/null; then
        eval "$(command -v bat)" -n "$@"
    else
        echo "Installing batcat now."
        sudo apt update
        sudo apt -y install bat
    fi
}