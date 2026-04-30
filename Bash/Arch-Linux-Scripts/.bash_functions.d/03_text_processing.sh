#!/usr/bin/env bash
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
findtext() {
  # Initialize flag variables and the search pattern
  local whole_word=0
  local case_exact=0
  local pattern=""

  # Iterate over all arguments
  for arg in "$@"; do
    case "$arg" in
      -w|--word)
        whole_word=1
        ;;
      -c|--case|-e|--exact)
        case_exact=1
        ;;
      -*)
        # If an unknown option is encountered, warn the user.
        echo "Unknown option: $arg"
        echo "Usage: findtext [options] \"<search string>\""
        return 1
        ;;
      *)
        # The first non-option argument is the search pattern
        if [ -z "$pattern" ]; then
          pattern="$arg"
        else
          echo "Unexpected argument: $arg"
          echo "Usage: findtext [options] \"<search string>\""
          return 1
        fi
        ;;
    esac
  done

  # Make sure a pattern was provided
  if [ -z "$pattern" ]; then
    echo "Usage: findtext [options] \"<search string>\""
    return 1
  fi

  # Clear the terminal screen
  clear

  # Set up the basic grep arguments.
  # -rn: search recursively and show line numbers.
  # --color=always: highlight matches.
  local args=( "-rn" "--color=always" )

  # By default, search is case-insensitive unless a case‑exact flag is given.
  if [ $case_exact -eq 0 ]; then
    args+=( "-i" )
  fi

  # If whole-word matching is enabled, add the ‑w flag.
  if [ $whole_word -eq 1 ]; then
    args+=( "-w" )
  fi

  # Specify file extensions to search: ts, tsx, and js.
  local ext_list="ts;tsx;js;py"
  IFS=';' read -ra exts <<< "$ext_list"
  for ext in "${exts[@]}"; do
    args+=( "--include=*.$ext" )
  done

  # Append the search pattern and the current directory.
  args+=( "$pattern" "." )

  # Execute grep with the constructed arguments,
  # then filter out unwanted directories (node_modules, dist, disabled).
  grep "${args[@]}" | grep -Ev 'node_modules/|dist/|disabled/'
}

# BATCAT COMMANDS
bat() {
    if command -v bat &>/dev/null; then
        bat "$@"
    else
        echo "Installing bat now."
        sudo pacman -S --noconfirm bat
    fi
}

batn() {
    if command -v bat &>/dev/null; then
        bat -n "$@"
    else
        echo "Installing bat now."
        sudo pacman -S --noconfirm bat
    fi
}

# Recursively search for a string, with optional extension filter and path exclusion
sst() {
  local usage="Usage: sst [--case] <search_pattern> \
[avoid_patterns separated by ';'] \
[extensions separated by ';'] \
[exclude_patterns separated by ';']

Quickly search files, excluding certain lines and paths.

Options:
  --case          Case-sensitive match (default is case-insensitive).
  -h, --help      Show this help and exit.

Arguments:
  search_pattern      Text (or regex) to find.
  avoid_patterns      (Optional) Semicolon list of strings; any result line containing these is dropped.
  extensions          (Optional) Semicolon list of extensions to include, e.g. 'ts;js;py'.
  exclude_patterns    (Optional) Semicolon list of path substrings to skip files/dirs."

  # Help
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "%s\n" "$usage"; return 0
  fi

  # Case flag?
  local case_sensitive=false
  if [[ "$1" == "--case" ]]; then
    case_sensitive=true
    shift
  fi

  # Must have at least a pattern
  if [[ $# -lt 1 ]]; then
    printf "Error: missing <search_pattern>.\n\n%s\n" "$usage" >&2
    return 1
  fi

  local pattern="$1"; shift
  local avoid_str="$1"; shift || true
  local extensions="$1"; shift || true
  local exclude_str="$1"; shift || true

  # Build grep args
  local args=( -rn --color=always )
  
  # default to case-insensitive unless --case passed
  if ! $case_sensitive; then
    args+=( -i )
  fi

  # always whole-word match
  args+=( -w )

  # Include only specified extensions
  if [[ -n "$extensions" ]]; then
    IFS=';' read -ra exts <<< "$extensions"
    for e in "${exts[@]}"; do
      args+=( --include="*.$e" )
    done
  fi

  # Exclude paths
  if [[ -n "$exclude_str" ]]; then
    IFS=';' read -ra excls <<< "$exclude_str"
    for x in "${excls[@]}"; do
      args+=( --exclude="*${x}*" --exclude-dir="*${x}*" )
    done
  fi

  # Run grep, then drop any lines containing avoid_patterns
  if [[ -n "$avoid_str" ]]; then
    IFS=';' read -ra avoids <<< "$avoid_str"
    local vopts=( -vF )
    for a in "${avoids[@]}"; do
      vopts+=( -e "$a" )
    done
    grep "${args[@]}" -- "$pattern" | grep "${vopts[@]}"
  else
    grep "${args[@]}" -- "$pattern"
  fi
}

ripgrep() {
  # --- 1. Pre-flight Checks ---
  if ! command -v rg &> /dev/null; then
    echo "Error: 'ripgrep' (rg) is not installed or not in your PATH." >&2
    return 1
  fi

  if [ -z "$1" ]; then
    echo "Usage: _rg \"<search_pattern>\" [\"<exclude_type1;exclude_type2>\"]" >&2
    return 1
  fi

  # --- 2. Build Arguments ---
  local search_term="$1"
  local exclude_types_string="$2"
  local rg_args=()

  # If an exclude string is provided, process it
  if [ -n "$exclude_types_string" ]; then
    local exclude_types
    IFS=';' read -ra exclude_types <<< "$exclude_types_string"

    for type in "${exclude_types[@]}"; do
      if [ -n "$type" ]; then
        # Use ripgrep's built-in type system to exclude file types
        rg_args+=(--type-not "$type")
      fi
    done
  fi

  # --- 3. Execute Search ---
  # The --fixed-strings flag has been removed to allow for regex/glob patterns.
  # The search term is now treated as a regular expression by default.
  rg "${rg_args[@]}" --line-number -- "$search_term"
}

# Alias to pass both arguments
alias _rg='ripgrep'

