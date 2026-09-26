#!/usr/bin/env bash

## SHELLCHECK ##
sc() {
    local file
    local -a files

    if (($# == 0)); then
        read -r -a files -p "Input the file path(s) to check: "
        echo
    else
        files=("$@")
    fi

    for file in "${files[@]}"; do
        box_out_banner "Parsing: $file"
        echo
        shellcheck --color=always -x --severity=warning --source-path="$PATH:$HOME/tmp:/etc:/usr/local/lib64:/usr/local/lib:/usr/local64:/usr/lib:/lib64:/lib:/lib32" "$file"
        echo
    done
}
