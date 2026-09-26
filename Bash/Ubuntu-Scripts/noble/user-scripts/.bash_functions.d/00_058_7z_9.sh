#!/usr/bin/env bash

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
