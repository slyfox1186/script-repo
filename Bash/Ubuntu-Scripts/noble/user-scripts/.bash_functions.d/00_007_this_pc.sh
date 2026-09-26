#!/usr/bin/env bash

## GET THE OS AND ARCH OF THE ACTIVE COMPUTER ##
this_pc() {
    local os version
    # shellcheck source=/etc/os-release
    source /etc/os-release
    os="${NAME:-Unknown}"
    version="${VERSION_ID:-Unknown}"

    printf 'Operating System: %s\n' "$os"
    printf 'Specific Version: %s\n' "$version"
    echo
}
