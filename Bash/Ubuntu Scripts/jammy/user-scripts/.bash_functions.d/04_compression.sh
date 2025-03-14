#!/usr/bin/env bash
# Compression and Archive Functions

## UNCOMPRESS FILES ##
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

# Gzip
gzip() {
    gzip -d "$@"
}

# Create a tar.gz file with max compression settings
7z_gz() {
    local source output
    if [[ -n "$1" ]]; then
        if [[ -f "$1.tar.gz" ]]; then
            sudo rm "$1.tar.gz"
        fi
        7z a -ttar -so -an "$1" | 7z a -tgzip -mx9 -mpass1 -si "$1.tar.gz"
    else
        read -p "Please enter the source folder path: " source
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [[ -f "$output.tar.gz" ]]; then
            sudo rm "$output.tar.gz"
        fi
        7z a -ttar -so -an "$source" | 7z a -tgzip -mx9 -mpass1 -si "$output.tar.gz"
    fi
}

# Create a tar.xz file with max compression settings using 7zip
7z_xz() {
    local source output
    if [[ -n "$1" ]]; then
        if [[ -f "$1.tar.xz" ]]; then
            sudo rm "$1.tar.xz"
        fi
        7z a -ttar -so -an "$1" | 7z a -txz -mx9 -si "$1.tar.xz"
    else
        read -p "Please enter the source folder path: " source
        read -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [[ -f "$output.tar.xz" ]]; then
            sudo rm "$output.tar.xz"
        fi
        7z a -ttar -so -an "$source" | 7z a -txz -mx9 -si "$output.tar.xz"
    fi
}

# Create a .7z file with max compression settings
# Optimized version combining the duplicate functions with a compression level parameter
7z_compress() {
  local choice source_dir archive_name compression_level="$1"
  
  # Default to level 9 if not specified
  [[ -z "$compression_level" ]] && compression_level=9
  
  # Validate compression level
  if [[ ! "$compression_level" =~ ^[1-9]$ ]]; then
    echo "Invalid compression level. Using default level 9."
    compression_level=9
  fi

  clear

  if [[ -d "$2" ]]; then
    source_dir="$2"
  else
    read -p "Please enter the source folder path: " source_dir
  fi

  if [[ ! -d "$source_dir" ]]; then
    echo "Invalid directory path: $source_dir"
    return 1
  fi

  archive_name="${source_dir##*/}.7z"

  7z a -y -t7z -m0=lzma2 -mx"$compression_level" "$archive_name" "$source_dir"/*

  echo
  echo "Do you want to delete the original directory?"
  echo "[1] Yes"
  echo "[2] No"
  echo
  read -p "Your choice is (1 or 2): " choice
  echo

  case $choice in
    1) rm -fr "$source_dir" && echo "Original directory deleted." ;;
    2|"") echo "Original directory not deleted." ;;
    *) echo "Bad user input. Original directory not deleted." ;;
  esac
}

# Maintain backward compatibility
7z_1() {
  7z_compress 1 "$1"
}

7z_5() {
  7z_compress 5 "$1"
}

7z_9() {
  7z_compress 9 "$1"
}

## RECURSIVELY UNZIP ZIP FILES AND NAME THE OUTPUT FOLDER THE SAME NAME AS THE ZIP FILE
zipr() {
    clear
    sudo find . -type f -iname "*.zip" -exec sh -c "unzip -o -d "${0%.*}" "$0"" "{}" \;
    sudo find . -type f -iname "*.zip" -exec trash-put "{}" \;
}