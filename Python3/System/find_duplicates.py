#!/usr/bin/env python3

import argparse
import cv2
import hashlib
import mimetypes
import multiprocessing
import os
import signal
import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed
from PIL import Image
from tqdm import tqdm

# Global flag to indicate if the script should exit
should_exit = False

def signal_handler(signum, frame):
    global should_exit
    should_exit = True
    print("\nCtrl+C pressed. Gracefully exiting...")

def get_file_signature(file_path):
    """Get a quick signature of the file based on its type."""
    mime_type, _ = mimetypes.guess_type(file_path)
    file_size = os.path.getsize(file_path)
    
    if mime_type and mime_type.startswith('video'):
        return get_video_signature(file_path, file_size)
    elif mime_type and mime_type.startswith('image'):
        return get_image_signature(file_path, file_size)
    else:
        return get_partial_hash(file_path, file_size)

def get_video_signature(file_path, file_size):
    """Get a signature for video files using metadata and partial content."""
    try:
        video = cv2.VideoCapture(file_path)
        fps = video.get(cv2.CAP_PROP_FPS)
        frame_count = int(video.get(cv2.CAP_PROP_FRAME_COUNT))
        width = int(video.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(video.get(cv2.CAP_PROP_FRAME_HEIGHT))
        video.release()
        
        # Combine metadata with partial hash
        partial_hash = get_partial_hash(file_path, file_size)
        return f"{file_size}_{fps}_{frame_count}_{width}_{height}_{partial_hash}"
    except Exception:
        return get_partial_hash(file_path, file_size)

def get_image_signature(file_path, file_size):
    """Get a signature for image files using metadata and partial content."""
    try:
        with Image.open(file_path) as img:
            width, height = img.size
            format = img.format
        
        # Combine metadata with partial hash
        partial_hash = get_partial_hash(file_path, file_size)
        return f"{file_size}_{width}_{height}_{format}_{partial_hash}"
    except Exception:
        return get_partial_hash(file_path, file_size)

def get_partial_hash(file_path, file_size):
    """Calculate a partial MD5 hash of a file."""
    hasher = hashlib.md5()
    with open(file_path, 'rb') as f:
        # Read first 64KB, middle 64KB, and last 64KB
        for offset in (0, max(0, file_size // 2 - 32768), max(0, file_size - 65536)):
            f.seek(offset)
            hasher.update(f.read(65536))
    return hasher.hexdigest()

def find_files(directory, file_types):
    """Recursively find files in the given directory with specified file types."""
    for root, dirs, files in os.walk(directory):
        if 'folder' in file_types:
            for dir_name in dirs:
                yield os.path.join(root, dir_name)
        
        for file in files:
            if not file_types or any(file.endswith(ft) for ft in file_types if ft != 'folder'):
                yield os.path.join(root, file)

def find_duplicates(directory, file_types):
    """Find duplicate files using parallel processing."""
    files = list(find_files(directory, file_types))
    
    # Use half of the available logical CPU cores
    num_workers = max(1, multiprocessing.cpu_count() // 2)
    
    duplicates = defaultdict(list)
    
    with ProcessPoolExecutor(max_workers=num_workers) as executor:
        futures = [executor.submit(get_file_signature, file) for file in files]
        
        for file, future in tqdm(zip(files, as_completed(futures)), total=len(files), desc="Scanning files", unit="file"):
            if should_exit:
                executor.shutdown(wait=False)
                return None
            
            file_signature = future.result()
            if file_signature:
                duplicates[file_signature].append(file)
    
    return {sig: paths for sig, paths in duplicates.items() if len(paths) > 1}

def delete_duplicates(duplicates):
    """Delete duplicate files, keeping the first occurrence."""
    for sig, paths in duplicates.items():
        print(f"\nDuplicate files with signature {sig}:")
        for idx, path in enumerate(paths):
            print(f"{idx + 1}. {path}")
        
        keep = input("Enter the number of the file to keep (or 'skip' to keep all): ").strip()
        
        if keep.lower() == 'skip':
            continue
        
        try:
            keep_idx = int(keep) - 1
            if 0 <= keep_idx < len(paths):
                for idx, path in enumerate(paths):
                    if idx != keep_idx:
                        os.remove(path)
                        print(f"Deleted: {path}")
            else:
                print("Invalid selection. Skipping this set of duplicates.")
        except ValueError:
            print("Invalid input. Skipping this set of duplicates.")

def main():
    parser = argparse.ArgumentParser(
        description="Find and optionally delete duplicate files in a specified directory.",
        epilog="""
Examples:
  Find duplicates in all files:
    python find_duplicates.py -d /path/to/directory

  Find duplicates only in MP4 and PNG files:
    python find_duplicates.py -d /path/to/directory -f .mp4 .png

  Find duplicates in PDF files and folders:
    python find_duplicates.py -d /path/to/directory -f .pdf folder

Note:
  - The script uses parallel processing to improve performance on multi-core systems.
  - You can interrupt the scan at any time by pressing Ctrl+C.
  - When specifying file types, you can use the format '.ext' or just 'ext'.
  - Use 'folder' as a file type to include directories in the search.
  - The script uses a combination of file size, metadata, and partial content for faster duplicate detection.
  - You will be prompted before any files are deleted.
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("-d", "--dir", required=True, help="Directory to scan for duplicates")
    parser.add_argument("-f", "--file-types", nargs='+', help="File types to search for (e.g., .mp4 .png folder)")
    args = parser.parse_args()

    directory = os.path.abspath(args.dir)
    if not os.path.isdir(directory):
        print(f"Error: {directory} is not a valid directory.")
        sys.exit(1)

    file_types = args.file_types if args.file_types else []
    file_types = [ft if ft.startswith('.') or ft == 'folder' else f'.{ft}' for ft in file_types]

    # Set up the signal handler for Ctrl+C
    signal.signal(signal.SIGINT, signal_handler)

    print(f"Scanning directory: {directory}")
    if file_types:
        print(f"Searching for file types: {', '.join(file_types)}")
    else:
        print("Searching for all file types")
    print("Press Ctrl+C to stop the scan at any time.")
    
    duplicates = find_duplicates(directory, file_types)

    if should_exit:
        print("Scan interrupted. Exiting...")
        sys.exit(0)

    if not duplicates:
        print("No duplicate files found.")
        return

    print(f"\nFound {sum(len(paths) for paths in duplicates.values()) - len(duplicates)} potential duplicate files.")

    delete = input("Do you want to delete duplicate files? (y/n): ").strip().lower()
    if delete == 'y':
        delete_duplicates(duplicates)
    else:
        print("No files were deleted.")

if __name__ == "__main__":
    main()
