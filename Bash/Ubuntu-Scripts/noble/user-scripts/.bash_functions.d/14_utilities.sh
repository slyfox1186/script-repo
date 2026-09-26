#!/usr/bin/env bash
# Shell Utility Functions

box_out_banner() {
    local line message space width
    message="$*"
    width=$((${#message} + 2))
    printf -v space '%*s' "$width" ''
    line=${space// /-}

    if [[ -t 1 ]] && command -v tput &>/dev/null; then
        tput bold
        tput setaf 3
    fi
    printf ' %s\n|%s|\n| ' "$line" "$space"
    if [[ -t 1 ]] && command -v tput &>/dev/null; then
        tput setaf 4
    fi
    printf '%s' "$message"
    if [[ -t 1 ]] && command -v tput &>/dev/null; then
        tput setaf 3
    fi
    printf ' |\n|%s|\n %s\n' "$space" "$line"
    if [[ -t 1 ]] && command -v tput &>/dev/null; then
        tput sgr0
    fi
}

# Get current time
st() {
    date +%r | cut -d " " -f1-2 | grep -E "^.*$"
}

## SOURCE FILES ##
sbrc() {
    source "$HOME/.bashrc"
    clear; ls -1AhFv --color --group-directories-first
}

spro() {
    # shellcheck source=/dev/null
    if source "$HOME/.profile"; then
        echo "The command was a success!"
    else
        echo "The command failed!"
    fi
    clear; ls -1AhFv --color --group-directories-first
}

# Clear Bash History
clearh() {
    history -c
    clear; ls -1AhFv
    echo -e "\n${GREEN}Bash History Cleared${NC}"
}

###############
## CLIPBOARD ##
###############

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
        pipe="$*"
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
        pipe="$*"
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
        xclip -i -rmlastnl -select clipboard < "$1"
    fi
}

# Reddit Downvote Calculator
rdvc() {
    declare -A args
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -u|--upvotes) args["total_upvotes"]="$2"; shift 2 ;;
            -p|--percentage) args["upvote_percentage"]="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: rdvc [OPTIONS]"
                echo "Calculate Reddit downvotes based on total upvotes and upvote percentage."
                echo
                echo "Options:"
                echo "  -u, --upvotes       Set the total number of upvotes"
                echo "  -p, --percentage    Set the upvote percentage"
                echo "  -h, --help          Display this help message"
                echo
                return 0
                ;;
            *)
                echo "Error: Unknown option '$1'."
                echo "Use -h or --help for usage information."
                return 1
                ;;
        esac
    done

    if [[ -z ${args["total_upvotes"]} || -z ${args["upvote_percentage"]} ]]; then
        echo "Error: Missing required arguments."
        echo "Use -h or --help for usage information."
        return 1
    fi

    local total_upvotes="${args["total_upvotes"]}"
    local upvote_percentage="${args["upvote_percentage"]}"

    upvote_percentage_decimal=$(bc <<< "scale=2; $upvote_percentage / 100")
    total_votes=$(bc <<< "scale=2; $total_upvotes / $upvote_percentage_decimal")
    total_votes_rounded=$(bc <<< "($total_votes + 0.5) / 1")
    downvotes=$(bc <<< "$total_votes_rounded - $total_upvotes")

    echo -e "Upvote percentage ranges for the first $total_upvotes downvotes:"
    for ((i=1; i<=total_upvotes; i++)); do
        lower_limit=$(bc <<< "scale=2; $total_upvotes / ($total_upvotes + $i) * 100")
        if [[ $i -lt $total_upvotes ]]; then
            next_lower_limit=$(bc <<< "scale=2; $total_upvotes / ($total_upvotes + $i + 1) * 100")
            next_lower_limit_adjusted=$(bc <<< "scale=2; $next_lower_limit + 0.01")
            echo "Downvotes $i: ${lower_limit}% to $next_lower_limit_adjusted%"
        else
            echo "Downvotes $i: ${lower_limit}% and lower"
        fi
    done

    echo
    echo "Total upvotes: $total_upvotes"
    echo "Upvote percentage: $upvote_percentage%"
    echo "Calculated downvotes: $downvotes"
}

display_help() {
    cat <<EOF
Usage: ${FUNCNAME[0]} [OPTIONS]

Calculate the number of downvotes on a Reddit post.

Options:
  -u, --upvotes <number>         Total number of upvotes on the post
  -p, --percentage <number>      Upvote percentage (without the % sign)
  -h, --help                     Display this help message and exit

Examples:
  ${FUNCNAME[0]} --upvotes 8 --percentage 83
EOF
}

# Expand common Conda, Git, and Pip shortcuts at the start of a command line.
_command_shortcut_completion() {
    case "${COMP_WORDS[0]}" in
        ca)    COMPREPLY=('conda activate ') ;;
        ci)    COMPREPLY=('conda install ') ;;
        cel)   COMPREPLY=('conda env list ') ;;
        cc)    COMPREPLY=('conda create --name ') ;;
        crm)   COMPREPLY=('conda env remove --name ') ;;
        cr)    COMPREPLY=('conda run --name ') ;;
        cu)    COMPREPLY=('conda update ') ;;
        gad)   COMPREPLY=('git add ') ;;
        gc)    COMPREPLY=('git clone ') ;;
        gcm)   COMPREPLY=('git commit --message ') ;;
        gp)    COMPREPLY=('git pull ') ;;
        gps)   COMPREPLY=('git push ') ;;
        gst)   COMPREPLY=('git status --short --branch ') ;;
        pipc)  COMPREPLY=('pip check ') ;;
        pipf)  COMPREPLY=('pip freeze ') ;;
        pipi)  COMPREPLY=('pip install ') ;;
        plist) COMPREPLY=('pip list ') ;;
        preq)  COMPREPLY=('pip install --requirement ') ;;
        pshow) COMPREPLY=('pip show ') ;;
        pipun) COMPREPLY=('pip uninstall ') ;;
        pipiu) COMPREPLY=('pip install --upgrade ') ;;
        *)     COMPREPLY=(); return 0 ;;
    esac

    compopt -o noquote -o nospace
}

# Keep Bash's normal command and filename completion as the fallback.
complete -o bashdefault -o default -F _command_shortcut_completion -I
