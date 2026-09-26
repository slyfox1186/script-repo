#!/usr/bin/env bash

pipua() {
    local outdated_json package_names package
    local status=0

    if ! outdated_json=$(pip list --outdated --exclude-editable --format=json); then
        return 1
    fi

    if ! package_names=$(python3 -c '
import json
import sys

for package in json.load(sys.stdin):
    print(package["name"])
' <<< "$outdated_json"); then
        printf '%s\n' 'pipua: failed to parse the list of outdated packages' >&2
        return 1
    fi

    if [[ -z "$package_names" ]]; then
        printf '%s\n' 'All non-editable packages are up to date.'
        return 0
    fi

    while IFS= read -r package; do
        if ! pip install -U "$package"; then
            status=1
        fi
    done <<< "$package_names"

    return "$status"
}
