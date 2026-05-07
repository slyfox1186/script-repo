#!/usr/bin/env python3

import subprocess
import os
import sys

# Configurable Variables
folderA = "/m/"
folderB = "/f/"
delete_extraneous = True  # Set to False to keep extraneous files in the destination

# Function to run rsync
def run_rsync(source, destination, delete):
    if not os.path.exists(source):
        sys.exit(f"Source directory not found: {source}")

    if not os.path.exists(destination):
        sys.exit(f"Destination directory not found: {destination}")

    rsync_command = ["rsync", "-avu", "--inplace"]
    if delete:
        rsync_command.append("--delete")
    rsync_command.extend([source, destination])

    try:
        subprocess.run(rsync_command, check=True)
        print(f"Successfully synchronized {source} to {destination}")
    except subprocess.CalledProcessError as e:
        sys.exit(f"Rsync failed: {e}")
    except Exception as e:
        sys.exit(f"An unexpected error occurred: {e}")

def main():
    # Perform safety checks before running rsync
    if folderA == folderB:
        sys.exit("Source and destination directories cannot be the same")

    # Sync from Folder A to Folder B
    run_rsync(folderA, folderB, delete_extraneous)

    # Sync from Folder B to Folder A
    run_rsync(folderB, folderA, delete_extraneous)

    print("Backup process completed successfully.")

if __name__ == "__main__":
    main()
