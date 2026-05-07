#!/usr/bin/env python3

import subprocess
import os
import sys

# Configurable Variables
folderA = "/m/"
folderB = "/f/"
delete_extraneous = False
exclusions_file = "exclusions.txt"  # File containing paths to exclude

# Function to read exclusion paths from a file
def read_exclusions(file_path):
    try:
        with open(file_path, 'r') as file:
            return [line.strip() for line in file if line.strip()]
    except FileNotFoundError:
        print(f"Exclusions file not found: {file_path}")
        return []

# Function to run rsync
def run_rsync(source, destination, delete, excludes):
    if not os.path.exists(source):
        sys.exit(f"Source directory not found: {source}")

    if not os.path.exists(destination):
        sys.exit(f"Destination directory not found: {destination}")

    rsync_command = ["rsync", "-avu", "--inplace"]
    if delete:
        rsync_command.append("--delete")
    for exclude in excludes:
        rsync_command.extend(["--exclude", exclude])
    rsync_command.extend([source, destination])

    try:
        subprocess.run(rsync_command, check=True)
        print(f"Successfully synchronized {source} to {destination}")
    except subprocess.CalledProcessError as e:
        sys.exit(f"Rsync failed: {e}")
    except Exception as e:
        sys.exit(f"An unexpected error occurred: {e}")

def main():
    if folderA == folderB:
        sys.exit("Source and destination directories cannot be the same")

    exclusions = read_exclusions(exclusions_file)

    run_rsync(folderA, folderB, delete_extraneous, exclusions)
    run_rsync(folderB, folderA, delete_extraneous, exclusions)

    print("Backup process completed successfully.")

if __name__ == "__main__":
    main()
