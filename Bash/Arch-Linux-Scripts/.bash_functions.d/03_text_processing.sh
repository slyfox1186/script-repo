#!/usr/bin/env bash
# Text Processing Functions

## AWK COMMANDS ##

# Remove duplicate lines: output to the terminal.
dedupe_lines() {
    awk '!seen[$0]++' "$1"
}

# Remove consecutive duplicate lines: output to the terminal.
dedupe_consecutive_lines() {
    awk 'f!=$0{print;f=$0}' "$1"
}

# Remove trailing spaces and duplicate lines in place.
dedupe_trimmed_file() {
    perl -i -lne "s/\s*$//; print if ! \$x{\$_}++" "$1"
    gnome-text-editor "$1"
}

# Install colordiff package
cdiff() {
    colordiff "$1" "$2"
}

## SED COMMANDS ##
fsed() {
    local otext rtext
    echo "This command is for sed to act only on files"
    echo

    if [[ -z "$1" ]]; then
        read -r -p "Enter the original text: " otext
        read -r -p "Enter the replacement text: " rtext
        echo
    else
        otext=$1
        rtext=$2
    fi

     sudo sed -i "s/${otext}/${rtext}/g" "$(find . -maxdepth 1 -type f)"
}

####################
## REGEX COMMANDS ##
####################

bvar() {
    local choice fname fname_tmp
    clear

    if [[ -z "$1" ]]; then
        read -r -p "Please enter the file path: " fname
        fname_tmp="$fname"
    else
        fname="$1"
        fname_tmp="$fname"
    fi

    if [[ -f "$fname" ]]; then
        fname+=".txt"
        mv "${fname_tmp}" "$fname"
    fi

    sed -e "s/\(\$\)\([A-Za-z0-9\_]*\)/\1{\2}/g" -e "s/\(\$\)\({}\)/\1/g" -e "s/\(\$\)\({}\)\({\)/\1\3/g" "$fname"

    printf "%s\n\n%s\n%s\n\n" \
        "Do you want to permanently change this file?" \
        "[1] Yes" \
        "[2] Exit"
    read -r -p "Your choices are ( 1 or 2): " choice
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
    local file target_dir temp_file

    for file in "$@"; do
        if [[ -f "$file" ]]; then
            target_dir=$(dirname -- "$file") || return 1
            temp_file=$(mktemp --tmpdir="$target_dir" ".${file##*/}.XXXXXX") || return 1
            if sed -e 's/${/$/g' -e 's/}//g' -- "$file" > "$temp_file"; then
                chmod --reference="$file" "$temp_file"
                mv -- "$temp_file" "$file"
                printf 'Modified file: %s\n' "$file"
            else
                rm -f -- "$temp_file"
                return 1
            fi
        else
            printf 'File not found: %s\n' "$file" >&2
        fi
    done
}

# BATCAT COMMANDS

bat() {
    local executable

    if executable=$(type -P batcat); then
        "$executable" "$@"
    elif executable=$(type -P bat); then
        "$executable" "$@"
    else
        echo "Installing batcat now."
        sudo apt update && sudo apt -y install bat
    fi
}

batn() {
    bat -n "$@"
}

# ripgrep_search - A versatile ripgrep function for recursive pattern matching
# Usage: ripgrep_search [options] pattern1 [pattern2 ...]
# Examples:
#   ripgrep_search "error" "warning"
#   ripgrep_search -i "TODO" "FIXME"
#   ripgrep_search --type py "import.*requests"
#   ripgrep_search -A 3 -B 3 "function.*main"

ripgrep_search() {
    # Check for help flags
    for arg in "$@"; do
        if [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
            cat << 'EOF'
ripgrep_search - A versatile ripgrep function for recursive pattern matching

USAGE:
    ripgrep_search [options] pattern1 [pattern2 ...]

OPTIONS:
    -h, --help              Show this help message
    [rg-options]            Any ripgrep options (e.g., -i, -A, -B, --type)

EXAMPLES:
    ripgrep_search "error" "warning"
        Search for both "error" and "warning" patterns

    ripgrep_search -i "TODO" "FIXME"
        Search case-insensitively for TODO and FIXME

    ripgrep_search --type py "import.*requests"
        Search for import patterns only in Python files

    ripgrep_search -A 3 -B 3 "function.*main"
        Show 3 lines before and after matching function main patterns

    rgs "error" "warning"
        Use the short alias (rgs)

    rgf -i "TODO" "FIXME"
        Use the short alias (rgf)

NOTE:
    All searches are recursive and show line numbers, filenames, and headings by default.
    Searches include hidden files (--hidden) and ignore VCS ignore files (--no-ignore-vcs).
    Results automatically exclude common directories: node_modules, dist, .next
    Each pattern is searched separately with clear section headers.
EOF
            return 0
        fi
    done

    if [ $# -eq 0 ]; then
        echo "Usage: ripgrep_search [options] pattern1 [pattern2 ...]"
        echo "Use -h or --help for detailed help"
        return 1
    fi

    # Extract options (starting with -) and patterns
    local rg_options=()
    local patterns=()

    while [ $# -gt 0 ]; do
        if [[ "$1" == -* ]]; then
            # Skip help flags as they were already processed
            if [[ "$1" != "-h" ]] && [[ "$1" != "--help" ]]; then
                rg_options+=("$1")
            fi
            shift
        else
            patterns+=("$1")
            shift
        fi
    done

    # Check if we have any patterns
    if [ ${#patterns[@]} -eq 0 ]; then
        echo "Error: At least one pattern must be provided"
        echo "Use -h or --help for usage information"
        return 1
    fi

      # Search for each pattern
    for pattern in "${patterns[@]}"; do
        echo "=== Searching for: $pattern ==="

        # Build the command for this specific pattern
        local cmd="rg -n --with-filename --heading --hidden --no-ignore-vcs"

        # Add global exclusions for common directories
        cmd="$cmd --glob='!node_modules' --glob='!dist' --glob='!.next'"

        # Add any additional options
        for option in "${rg_options[@]}"; do
            cmd="$cmd $option"
        done

        # Add the pattern and search current directory (.)
        cmd="$cmd '$pattern' ."

        # Execute the command
        eval "$cmd"
        echo ""
    done
}

# Alias for quick access
alias rgs='ripgrep_search'
