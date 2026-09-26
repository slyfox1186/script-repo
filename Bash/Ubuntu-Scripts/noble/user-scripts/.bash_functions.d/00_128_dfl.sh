#!/usr/bin/env bash

dfl() {
  if [ -z "$1" ]; then
    echo "Please provide the full path of a folder as an argument."
    return 1
  fi

  if [ ! -d "$1" ]; then
    echo "The provided path is not a valid directory."
    return 1
  fi

  echo "How do you want to display the files?"
  echo "1. By name"
  echo "2. By date installed"
  echo "3. By date modified"
  echo "4. By date accessed"
  echo "5. By date created"
  echo "6. By size"

  read -r -p "Enter your choice (1-6): " choice

  case $choice in
    1)
      ls -1 "$1"
      ;;
    2)
      ls -1tr "$1"
      ;;
    3)
      ls -1t "$1"
      ;;
    4)
      ls -1u "$1"
      ;;
    5)
      ls -1U "$1"
      ;;
    6)
      ls -1S "$1"
      ;;
    *)
      echo "Invalid choice. Please enter a number between 1 and 6."
      ;;
  esac
}
