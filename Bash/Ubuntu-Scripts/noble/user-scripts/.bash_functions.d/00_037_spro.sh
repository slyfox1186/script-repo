#!/usr/bin/env bash

spro() {
    # shellcheck source=/dev/null
    if source "$HOME/.profile"; then
        echo "The command was a success!"
    else
        echo "The command failed!"
    fi
    clear; ls -1AhFv --color --group-directories-first
}
