#!/usr/bin/env bash

untar() {
    local archive dirname ext flag USER=$(whoami) supported_ext="7z bz2 gz lz tgz xz zip"

    for archive in *; do
        ext="${archive##*.}"
        [[ ! " $supported_ext " =~ " $ext " ]] && continue

        dirname="${archive%.*}"
        [[ "$archive" =~ \.tar\.(gz|bz2|lz|xz)$ ]] && dirname="${dirname%.*}"
        mkdir -p "$dirname"

        case "$ext" in
            7z) sudo 7z x -y "$archive" -o"$dirname" ;;
            zip) temp_dir=$(mktemp -d)
                 sudo unzip "$archive" -d "$temp_dir"
                 items=("$temp_dir"/*)
                 item_dirname="${items[0]##*/}"
                 if [[ "${#items[@]}" -eq 1 && -d "${items[0]}" && "$item_dirname" == "$dirname" ]]; then
                     sudo mv "${items[0]}"/* "$dirname"
                 else
                     sudo mv "$temp_dir"/* "$dirname"
                 fi
                 sudo rm -fr "$temp_dir"
                 ;;
            gz|tgz|bz2|xz|lz)
                sudo tar -xf "$archive" -C "$dirname" --strip-components 1 ;;
        esac

        for dir in *; do
            if [[ -d "$dir" ]]; then
                sudo chown -R "$USER":"$USER" "$dir"
                sudo chmod -R 755 "$dir"
            fi
        done
    done
}

untar
