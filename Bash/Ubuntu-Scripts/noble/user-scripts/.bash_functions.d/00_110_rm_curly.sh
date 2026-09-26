#!/usr/bin/env bash

rm_curly() {
    local file target_dir temp_file

    for file in "$@"; do
        if [[ -f "$file" ]]; then
            target_dir=$(dirname -- "$file") || return 1
            temp_file=$(mktemp --tmpdir="$target_dir" ".${file##*/}.XXXXXX") || return 1
            if sed -e 's/${/$/g' -e 's/}//g' -- "$file" > "$temp_file"; then
                chmod --reference="$file" "$temp_file"
                mv -- "$temp_file" "$file"
                printf 'Modified file: %s\n' "$file"
            else
                rm -f -- "$temp_file"
                return 1
            fi
        else
            printf 'File not found: %s\n' "$file" >&2
        fi
    done
}
