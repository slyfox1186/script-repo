#!/usr/bin/env python3

import os
import sys

def rename_files(directory, prefix):
    try:
        for filename in os.listdir(directory):
            old_file = os.path.join(directory, filename)
            new_file = os.path.join(directory, f"{prefix}_{filename}")
            os.rename(old_file, new_file)
        print("Files renamed successfully.")
    except Exception as e:
        print(f"Error: {e}")

def main():
    if len(sys.argv) != 3:
        print_help()
        sys.exit(1)

    directory = sys.argv[1]
    prefix = sys.argv[2]

    if not os.path.isdir(directory):
        print("Error: Directory does not exist.")
        sys.exit(1)

    rename_files(directory, prefix)

def print_help():
    print("Usage: rename_files.py <directory> <prefix>")
    print("Renames all files in the specified directory by appending the given prefix.")
    print("Arguments:")
    print("  <directory>  Path to the directory containing files to rename")
    print("  <prefix>     Prefix to append to each file name")

if __name__ == "__main__":
    main()
