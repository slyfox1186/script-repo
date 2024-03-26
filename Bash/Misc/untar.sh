#!/usr/bin/env bash

untar() {
    local archive dirname ext USER=$(whoami) approved="7z zip gz tgz bz2 xz lz"

    for archive in *.*; do
        ext="${archive##*.}"
        if [[ ! " $approved " =~ " $ext " ]]; then
            continue
        fi

        dirname="${archive%.*}"
        if [[ "$archive" =~ \.tar\.(gz|bz2|xz|lz)$ ]]; then
            dirname="${dirname%.*}"
        fi

        mkdir -p "$dirname"

        case "$ext" in
            7z) sudo 7z x -y "$archive" -o"$dirname" ;;
            zip) temp_dir=$(mktemp -d)
                 sudo unzip "$archive" -d "$temp_dir"
                 items=("$temp_dir"/* "$temp_dir"/.*) # Include hidden files
                 if [[ ${#items[@]} -eq 3 && -d "${items[0]}" && "${items[0]##*/}" == "$dirname" ]]; then
                     sudo mv "${items[0]}"/* "${items[0]}/".* "$dirname" 2>/dev/null
                 else
                     sudo mv "$temp_dir"/* "$temp_dir"/.* "$dirname" 2>/dev/null
                 fi
                 sudo rm -rf "$temp_dir"
                 ;;
            gz|tgz|bz2|xz|lz)
                 sudo tar -xf "$archive" -C "$dirname" --strip-components 1 ;;
        esac
    done

    for dir in *; do
        if [ -d "$dir" ]; then
            sudo chown -R "$USER":"$USER" "$dir"
            sudo chmod -R 755 "$dir"
        fi
    done
}

untar
