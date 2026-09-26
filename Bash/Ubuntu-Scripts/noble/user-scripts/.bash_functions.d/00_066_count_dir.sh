#!/usr/bin/env bash

## Count files in the directory
count_dir() {
    local keep_count
    keep_count=$(find . -maxdepth 1 -type f | wc -l)
    echo "The total directory file count is (non-recursive): $keep_count"
    echo
}
