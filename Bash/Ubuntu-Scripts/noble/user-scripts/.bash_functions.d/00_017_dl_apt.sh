#!/usr/bin/env bash

# Download an APT package + all its dependencies in one go
dl_apt() {
    local -a urls

    if [[ -z "${1-}" ]]; then
        printf 'Usage: dl_apt PACKAGE\n' >&2
        return 1
    fi

    mapfile -t urls < <(apt-get --print-uris -qq --reinstall install "$1" 2>/dev/null | cut -d"'" -f2)
    ((${#urls[@]} > 0)) || return 1
    wget --show-progress -cq -- "${urls[@]}"
    clear; ls -1AhFv --color --group-directories-first
}
