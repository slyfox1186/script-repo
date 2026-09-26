#!/usr/bin/env bash

# AI Existing Instructions
aie() {
    local arg1="$1" arg2="$2"

    [[ ! -f $HOME/custom-scripts/instructions-existing.sh ]] && {
        echo "Please create or install the bash script: $HOME/custom-scripts/instructions-existing.sh"
        return 1
    }

    bash "$HOME/custom-scripts/instructions-existing.sh" "$arg1" "$arg2"
}
