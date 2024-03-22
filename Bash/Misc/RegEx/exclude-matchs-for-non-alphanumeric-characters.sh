#!/usr/bin/env bash

excluded_chars='*&^%$#@!\\\_/?\]\[\(\)<>;:=+|{}'

while (($# > 0)); do
    output=$(echo "$1" | tr -d "$excluded_chars")
    if [[ -n "$output" ]]; then
        echo "$output"
        exit 0
    fi
    shift
done
