#!/usr/bin/env bash
# Compression and Archive Functions

## UNCOMPRESS FILES ##
untar() {
    local archive dirname ext USER=$(whoami) supported_ext="7z bz2 gz lz tgz xz zip"

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

        if [[ -d "$dirname" ]]; then
            sudo chown -R "$USER":"$USER" "$dirname"
            sudo chmod -R 755 "$dirname"
        fi
    done
}

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

# Print a listing that changes whenever an entry under the directory is added,
# removed, resized, or modified.
_7z_dir_snapshot() {
  (set -o pipefail; find "$1" -printf '%P\t%y\t%s\t%T@\n' | LC_ALL=C sort)
}

# Archive the contents of a directory, hidden entries included, into
# ./<directory name><extension>, then offer to delete the directory. Deletion is
# offered only when 7-Zip reports complete success, the new archive passes
# `7z t`, the archive lies outside the directory, and the directory has not
# changed since it was read.
# Usage: _7z_archive_then_offer_delete <source_dir> <extension> <7z switches...>
_7z_archive_then_offer_delete() {
  local source_dir="$1" extension="$2" archive_name archive_parent source_real snapshot status choice
  shift 2

  while [[ "$source_dir" == */ && "$source_dir" != "/" ]]; do
    source_dir="${source_dir%/}"
  done

  if [[ ! -d "$source_dir" ]]; then
    echo "Invalid directory path: $source_dir"
    return 1
  fi

  source_real=$(realpath -- "$source_dir") || return 1
  if [[ -z "$(find "$source_real" -mindepth 1 -print -quit)" ]]; then
    echo "Source directory is empty: $source_dir"
    return 1
  fi

  archive_name="${source_dir##*/}$extension"
  archive_parent=$(pwd -P)
  if [[ "$archive_parent/" == "${source_real%/}/"* ]]; then
    echo "Refusing to write $archive_name inside the directory being archived; run this from outside $source_dir." >&2
    return 1
  fi
  if [[ -e "$archive_name" || -L "$archive_name" ]]; then
    echo "$archive_parent/$archive_name already exists and 7-Zip would merge into it; move or delete it first." >&2
    return 1
  fi

  if ! snapshot=$(_7z_dir_snapshot "$source_real"); then
    echo "Could not read every entry in $source_dir; nothing was archived." >&2
    return 1
  fi

  7z a -y "$@" -- "$archive_name" "$source_dir/."
  status=$?
  if (( status != 0 )); then
    rm -f -- "$archive_name"
    echo "7-Zip failed (exit $status); the original directory was kept: $source_dir" >&2
    return 1
  fi

  if ! 7z t -- "$archive_name" >/dev/null; then
    rm -f -- "$archive_name"
    echo "The new archive failed its integrity test and was removed; the original directory was kept: $source_dir" >&2
    return 1
  fi

  if [[ "$(_7z_dir_snapshot "$source_real")" != "$snapshot" ]]; then
    echo "$source_dir changed while it was being archived, so $archive_name may not match it; the original directory was kept." >&2
    return 1
  fi

  echo
  echo "Do you want to delete the original directory?"
  echo "[1] Yes"
  echo "[2] No"
  echo
  read -rp "Your choice is (1 or 2): " choice
  echo

  case $choice in
    1)
      if [[ "$(_7z_dir_snapshot "$source_real")" != "$snapshot" ]]; then
        echo "$source_dir changed after it was archived; original directory not deleted." >&2
        return 1
      fi
      rm -fr -- "$source_dir" && echo "Original directory deleted."
      ;;
    2|"") echo "Original directory not deleted." ;;
    *) echo "Bad user input. Original directory not deleted." ;;
  esac
}

# Create a .7z file with max compression settings
# Optimized version combining the duplicate functions with a compression level parameter
7z_compress() {
  local source_dir compression_level="$1"

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

  _7z_archive_then_offer_delete "$source_dir" .7z -t7z -m0=lzma2 -mx"$compression_level"
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
    sudo find . -type f -iname "*.zip" -exec sh -c 'unzip -o -d "${1%.*}" "$1"' _ {} \;
    sudo find . -type f -iname "*.zip" -exec trash-put {} \;
}