#!/bin/bash

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
