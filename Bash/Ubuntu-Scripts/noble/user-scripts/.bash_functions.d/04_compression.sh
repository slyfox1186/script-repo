#!/usr/bin/env bash
# Compression and Archive Functions

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

# Gzip
gzip() {
    command gzip -d "$@"
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
        read -r -p "Please enter the source folder path: " source
        read -r -p "Please enter the destination archive path (w/o extension): " output
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
        read -r -p "Please enter the source folder path: " source
        read -r -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [[ -f "$output.tar.xz" ]]; then
            sudo rm "$output.tar.xz"
        fi
        7z a -ttar -so -an "$source" | 7z a -txz -mx9 -si "$output.tar.xz"
    fi
}

# Create a .7z file with max compression settings

7z_1() {
  local choice source_dir archive_name

  clear

  if [[ -d "$1" ]]; then
    source_dir="$1"
  else
    read -r -p "Please enter the source folder path: " source_dir
  fi

  if [[ ! -d "$source_dir" ]]; then
    echo "Invalid directory path: $source_dir"
    return 1
  fi

  archive_name="${source_dir##*/}.7z"

  7z a -y -t7z -m0=lzma2 -mx1 "$archive_name" "$source_dir"/*

  echo
  echo "Do you want to delete the original directory?"
  echo "[1] Yes"
  echo "[2] No"
  echo
  read -r -p "Your choice is (1 or 2): " choice
  echo

  case $choice in
    1) rm -fr "$source_dir" && echo "Original directory deleted." ;;
    2|"") echo "Original directory not deleted." ;;
    *) echo "Bad user input. Original directory not deleted." ;;
  esac
}

7z_5() {
  local choice source_dir archive_name

  clear

  if [[ -d "$1" ]]; then
    source_dir="$1"
  else
    read -r -p "Please enter the source folder path: " source_dir
  fi

  if [[ ! -d "$source_dir" ]]; then
    echo "Invalid directory path: $source_dir"
    return 1
  fi

  archive_name="${source_dir##*/}.7z"

  7z a -y -t7z -m0=lzma2 -mx5 "$archive_name" "$source_dir"/*

  echo
  echo "Do you want to delete the original directory?"
  echo "[1] Yes"
  echo "[2] No"
  echo
  read -r -p "Your choice is (1 or 2): " choice
  echo

  case $choice in
    1) rm -fr "$source_dir" && echo "Original directory deleted." ;;
    2|"") echo "Original directory not deleted." ;;
    *) echo "Bad user input. Original directory not deleted." ;;
  esac
}

7z_9() {
  local choice source_dir archive_name

  clear

  if [[ -d "$1" ]]; then
    source_dir="$1"
  else
    read -r -p "Please enter the source folder path: " source_dir
  fi

  if [[ ! -d "$source_dir" ]]; then
    echo "Invalid directory path: $source_dir"
    return 1
  fi

  archive_name="${source_dir##*/}.7z"

  7z a -y -t7z -m0=lzma2 -mx9 "$archive_name" "$source_dir"/*

  echo
  echo "Do you want to delete the original directory?"
  echo "[1] Yes"
  echo "[2] No"
  echo
  read -r -p "Your choice is (1 or 2): " choice
  echo

  case $choice in
    1) rm -fr "$source_dir" && echo "Original directory deleted." ;;
    2|"") echo "Original directory not deleted." ;;
    *) echo "Bad user input. Original directory not deleted." ;;
  esac
}

## RECURSIVELY UNZIP ZIP FILES AND NAME THE OUTPUT FOLDER THE SAME NAME AS THE ZIP FILE
zipr() {
    clear
    find . -type f -iname '*.zip' -exec sh -c 'for archive do unzip -o -d "${archive%.*}" "$archive" && trash-put "$archive"; done' sh {} +
}
