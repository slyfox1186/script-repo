#!/usr/bin/env bash

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
