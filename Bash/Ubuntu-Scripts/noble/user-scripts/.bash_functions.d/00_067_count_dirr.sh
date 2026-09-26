#!/usr/bin/env bash

count_dirr() {
    local keep_count
    clear
    keep_count=$(find . -type f | wc -l)
    echo "The total directory file count is (recursive): $keep_count"
    echo
}
