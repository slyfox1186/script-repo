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

# Remove trailing spaces and duplicate lines in place, then open the result.
dedupe_trimmed_file() {
    perl -i -lne "s/\s*$//; print if ! \$x{\$_}++" "$1" || return
    gnome-text-editor "$1" &>/dev/null &
}

## SED COMMANDS ##

# Usage: fsed [PATTERN REPLACEMENT]
# Replaces a sed basic regular expression in every file directly inside the current folder.
# A "/" in either argument is escaped, so paths work without manual quoting.
fsed() {
    local answer pattern replacement
    local -a files=() matched=()

    if (($# == 0)); then
        read -r -p "Enter the original text: " pattern || return 1
        read -r -p "Enter the replacement text: " replacement || return 1
        echo
    elif (($# == 2)); then
        pattern=$1
        replacement=$2
    else
        printf 'Usage: fsed [PATTERN REPLACEMENT]\n' >&2
        return 1
    fi
    if [[ -z "$pattern" ]]; then
        printf 'The original text cannot be empty.\n' >&2
        return 1
    fi

    mapfile -d '' files < <(find . -maxdepth 1 -type f -print0)
    ((${#files[@]})) && mapfile -t matched < <(grep -l -- "$pattern" "${files[@]}")
    if ((${#matched[@]} == 0)); then
        printf 'No file in %s contains: %s\n' "$PWD" "$pattern"
        return 1
    fi
    printf 'Files to change:\n'
    printf '  %s\n' "${matched[@]}"
    read -r -p 'Apply the replacement to these files? [y/N] ' answer || return 1
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || return 1

    sed -i -- "s/${pattern//\//\\/}/${replacement//\//\\/}/g" "${matched[@]}"
}

####################
## REGEX COMMANDS ##
####################

# Usage: bvar [FILE]
# Shows the effect of rewriting $name and $1 as ${name} and ${1}, then optionally applies it.
bvar() {
    local choice fname="${1-}"
    local -a expressions=(-e "s/\\\$([A-Za-z_][A-Za-z0-9_]*)/\${\\1}/g" -e "s/\\\$([0-9])/\${\\1}/g")

    if [[ -z "$fname" ]]; then
        read -r -p "Please enter the file path: " fname || return 1
    fi
    if [[ ! -f "$fname" ]]; then
        printf 'File not found: %s\n' "$fname" >&2
        return 1
    fi

    if sed -E "${expressions[@]}" -- "$fname" | diff -u --label "$fname" --label "$fname (braced)" -- "$fname" -; then
        printf 'No unbraced variables found.\n'
        return 0
    fi

    printf "\n%s\n\n%s\n%s\n\n" \
        "Do you want to permanently change this file?" \
        "[1] Yes" \
        "[2] Exit"
    read -r -p "Your choices are (1 or 2): " choice || return 1
    case "$choice" in
        1) sed -E -i "${expressions[@]}" -- "$fname" ;;
        *) return 0 ;;
    esac
}

# Usage: rm_curly FILE...
# Rewrites ${name} as $name only where the next character cannot extend the name, so
# ${name}_suffix, ${10} and every other brace are left untouched.
rm_curly() {
    local file status=0

    for file in "$@"; do
        if [[ -f "$file" ]]; then
            if perl -i -pe 's/\$\{([A-Za-z_][A-Za-z0-9_]*|[0-9])\}(?![A-Za-z0-9_])/\$$1/g' -- "$file"; then
                printf 'Modified file: %s\n' "$file"
            else
                status=1
            fi
        else
            printf 'File not found: %s\n' "$file" >&2
            status=1
        fi
    done
    return "$status"
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
ripgrep_search() {
    local arg pattern
    local -a rg_options=() patterns=()

    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
            break
        fi
        if [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
            cat << 'HELP'
ripgrep_search - A versatile ripgrep function for recursive pattern matching

USAGE:
    ripgrep_search [options] pattern1 [pattern2 ...]
    ripgrep_search [options] -- pattern1 [pattern2 ...]

OPTIONS:
    -h, --help              Show this help message
    -e PATTERN              Add a pattern, including one that starts with "-"
    [rg-options]            Any ripgrep options (e.g., -i, -A 3, -B 3, --type py)

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

NOTE:
    All searches are recursive and show line numbers, filenames, and headings by default.
    Searches include hidden files (--hidden) and ignore VCS ignore files (--no-ignore-vcs).
    Results automatically exclude common directories: node_modules, dist, .next
    Each pattern is searched separately with clear section headers.
    Options that take a value accept it as the next argument or after "=".
HELP
            return 0
        fi
    done

    while (($#)); do
        case "$1" in
            --)
                shift
                patterns+=("$@")
                break
                ;;
            -e|--regexp)
                (($# >= 2)) || { printf 'Error: %s needs a pattern\n' "$1" >&2; return 1; }
                patterns+=("$2")
                shift 2
                ;;
            -A|-B|-C|-t|-T|-g|-m|-M|-j|-d|-E|-r|-f|--after-context|--before-context|--context|\
            --type|--type-not|--type-add|--type-clear|--glob|--iglob|--max-count|--max-columns|\
            --max-depth|--max-filesize|--threads|--encoding|--sort|--sortr|--replace|--file|\
            --context-separator|--field-match-separator|--path-separator|--colors|--color)
                (($# >= 2)) || { printf 'Error: %s needs a value\n' "$1" >&2; return 1; }
                rg_options+=("$1" "$2")
                shift 2
                ;;
            -*)
                rg_options+=("$1")
                shift
                ;;
            *)
                patterns+=("$1")
                shift
                ;;
        esac
    done

    if ((${#patterns[@]} == 0)); then
        echo "Error: At least one pattern must be provided"
        echo "Use -h or --help for usage information"
        return 1
    fi

    for pattern in "${patterns[@]}"; do
        echo "=== Searching for: $pattern ==="
        rg -n --with-filename --heading --hidden --no-ignore-vcs \
            --glob '!node_modules' --glob '!dist' --glob '!.next' \
            "${rg_options[@]}" -e "$pattern" -- .
        echo ""
    done
}

# Alias for quick access
alias rgs='ripgrep_search'
