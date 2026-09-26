#!/usr/bin/env bash

# Copy file
cpf() {
    [[ ! -d "$HOME/tmp" ]] && mkdir -p "$HOME/tmp"
    cp "$1" "$HOME/tmp/$1"
    chown -R "$USER:$USER" "$HOME/tmp/$1"
    chmod -R 744 "$HOME/tmp/$1"
    clear
    ls -1AhFv --color --group-directories-first
}
