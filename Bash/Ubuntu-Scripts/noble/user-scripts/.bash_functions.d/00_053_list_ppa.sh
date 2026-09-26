#!/usr/bin/env bash

## LIST PPA REPOS
list_ppa() {
    local apt entry host user ppa

    while IFS= read -r -d '' apt; do
        grep -Po "(?<=^deb\s).*?(?=#|$)" "$apt" | while read -r entry; do
            host=$(echo "$entry" | cut -d/ -f3)
            user=$(echo "$entry" | cut -d/ -f4)
            ppa=$(echo "$entry" | cut -d/ -f5)
            if [[ "ppa.launchpad.net" = "$host" ]]; then
                echo sudo apt-add-repository ppa:"$user/$ppa"
            else
                echo sudo apt-add-repository \"deb "$entry"\"
            fi
        done
    done < <(find /etc/apt/ -type f -name '*.list' -print0)
}
