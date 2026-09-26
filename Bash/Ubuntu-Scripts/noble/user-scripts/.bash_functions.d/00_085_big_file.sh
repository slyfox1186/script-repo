#!/usr/bin/env bash

big_file() {
    local count="${1:-20}"

    [[ "$count" =~ ^[1-9][0-9]*$ ]] || {
        printf 'Usage: big_file [POSITIVE_COUNT]\n' >&2
        return 1
    }
    find . -type f -print0 | du -ha --files0-from=- | LC_ALL=C sort -rh | head -n "$count"
}
