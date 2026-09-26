#!/usr/bin/env bash

## UNCOMPRESS FILES ##
untar() (
    local archive dirname ext item_dirname source_dir temp_dir
    local -a items

    for archive in *; do
        ext="${archive##*.}"
        case "$ext" in
            7z|bz2|gz|lz|tgz|xz|zip) ;;
            *) continue ;;
        esac

        dirname="${archive%.*}"
        [[ "$archive" =~ \.tar\.(gz|bz2|lz|xz)$ ]] && dirname="${dirname%.*}"
        mkdir -p "$dirname"

        case "$ext" in
            7z) 7z x -y "$archive" -o"$dirname" ;;
            zip) temp_dir=$(mktemp -d) || return 1
                 item_dirname=""
                 if ! unzip -o "$archive" -d "$temp_dir"; then
                     rm -rf -- "$temp_dir"
                     return 1
                 fi
                 shopt -s nullglob dotglob
                 items=("$temp_dir"/*)
                 shopt -u nullglob dotglob
                 source_dir="$temp_dir"
                 if [[ "${#items[@]}" -eq 1 && -d "${items[0]}" ]]; then
                     item_dirname="${items[0]##*/}"
                 fi
                 if [[ "${#items[@]}" -eq 1 && "$item_dirname" == "$dirname" ]]; then
                     source_dir="${items[0]}"
                 fi
                 if ((${#items[@]} > 0)); then
                     if ! cp -a -- "$source_dir/." "$dirname/"; then
                         rm -rf -- "$temp_dir"
                         return 1
                     fi
                 fi
                 rm -rf -- "$temp_dir"
                 ;;
            gz|tgz|bz2|xz|lz)
                tar -xf "$archive" -C "$dirname" --strip-components 1 ;;
        esac
    done
)
