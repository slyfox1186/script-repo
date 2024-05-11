#!/usr/bin/env python3

import os
import argparse
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
import subprocess

def clear_screen():
    subprocess.run(['clear' if os.name == 'posix' else 'cls'], shell=True)

def get_file_extensions():
    categories = {
        1: ('archives', ['.zip', '.rar', '.tar', '.gz', '.7z', '.bz2']),
        2: ('documents', ['.pdf', '.docx', '.doc', '.txt', '.odt', '.rtf', '.xlsx', '.xls', '.pptx', '.ppt']),
        3: ('images', ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.svg']),
        4: ('music', ['.mp3', '.wav', '.aac', '.flac', '.ogg', '.m4a']),
        5: ('programming', ['.py', '.js', '.java', '.c', '.cpp', '.cs', '.php', '.rb', '.go']),
        6: ('scripting languages', ['.sh', '.bash', '.ps1', '.bat', '.vbs']),
        7: ('videos', ['.mp4', '.avi', '.mkv', '.flv', '.wmv', '.mov']),
        8: ('web files', ['.html', '.css', '.scss', '.js', '.php', '.asp', '.jsp']),
        9: ('custom', 'Enter custom extensions separated by commas (no dots), e.g., jpg,png,gif')
    }
    
    print("Select a category of files to search for:")
    for key, (category, extensions) in categories.items():
        if key != 9:
            print(f"{key}: {category} ({', '.join(extensions)})")
        else:
            print(f"{key}: {extensions}")

    while True:
        try:
            choice = int(input("Enter the number of your choice: "))
            if choice in categories:
                clear_screen()
                if choice != 9:
                    return categories[choice][1]
                else:
                    custom_ext = input("Enter custom extensions separated by commas, e.g., jpg,png,gif: ")
                    return ['.' + ext.strip() for ext in custom_ext.split(',')]
            else:
                print("Invalid choice. Please try again.")
        except ValueError:
            print("Invalid input. Please enter a valid number.")

# Define this at the top level so it can be pickled by multiprocessing
def scan_directory(directory, file_extensions, exclude_text, include_text, min_size, max_size, verbose, print_sizes):
    video_files = []
    with os.scandir(directory) as entries:
        for entry in entries:
            if entry.is_dir():
                # Recursively scan the subdirectory
                video_files.extend(scan_directory(entry.path, file_extensions, exclude_text, include_text, min_size, max_size, verbose, print_sizes))
            elif entry.is_file() and entry.name.lower().endswith(tuple(file_extensions)):
                full_path = entry.path
                file_size = entry.stat().st_size
                if exclude_text and exclude_text.lower() in full_path.lower():
                    if verbose:
                        print(f"Excluding: {full_path}")
                    continue
                if include_text and include_text.lower() not in full_path.lower():
                    if verbose:
                        print(f"Not including: {full_path}")
                    continue
                if (min_size and file_size < min_size) or (max_size and file_size > max_size):
                    if verbose:
                        print(f"Excluding due to size constraints: {full_path}")
                    continue
                # Collect file path and size
                video_files.append((full_path, file_size))
                if print_sizes:
                    size_in_mb = file_size / 1048576
                    print(f"{full_path} - {size_in_mb:.2f} MB")
                else:
                    print(full_path)
                if verbose:
                    print(f"Adding: {full_path}")
    return video_files

def find_files(directory, file_extensions, exclude_text=None, include_text=None, min_size=None, max_size=None, sort_by_size=False, verbose=False, print_sizes=False):
    path = Path(directory)
    if not path.exists() or not path.is_dir():
        print(f"Error: The directory {directory} does not exist or is not a directory.")
        return []

    file_list = []

    # Use multiprocessing to scan directories concurrently
    with ProcessPoolExecutor() as executor:
        # Submit jobs to executor
        futures = []
        for sub_dir in path.iterdir():
            if sub_dir.is_dir():
                future = executor.submit(scan_directory, sub_dir, file_extensions, exclude_text, include_text, min_size, max_size, verbose, print_sizes)
                futures.append(future)

        # Collect results
        for future in futures:
            file_list.extend(future.result())

    # Sort files by size if requested
    if sort_by_size:
        file_list.sort(key=lambda x: x[1], reverse=True)  # Sort by size (stored in tuple)
        if verbose:
            print("Files have been sorted by size.")

    return file_list

def main():
    parser = argparse.ArgumentParser(description='Find, sort, and exclude files efficiently.')
    parser.add_argument('-d', '--directory', required=True, help='Directory to search for files')
    parser.add_argument('-o', '--output', help='Output file to log results (optional)')
    parser.add_argument('-s', '--size', action='store_true', help='Sort results by file size, from largest to smallest')
    parser.add_argument('-e', '--exclude', help='Text pattern to exclude from file paths')
    parser.add_argument('-i', '--include', help='Text pattern to include in file paths')
    parser.add_argument('--min-size', type=int, help='Minimum file size in megabytes')
    parser.add_argument('--max-size', type=int, help='Maximum file size in megabytes')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    parser.add_argument('--print-sizes', action='store_true', help='Print file sizes next to paths in megabytes')

    args = parser.parse_args()

    min_size_bytes = args.min_size * 1048576 if args.min_size else None
    max_size_bytes = args.max_size * 1048576 if args.max_size else None

    file_extensions = get_file_extensions()

    try:
        files = find_files(args.directory, file_extensions, exclude_text=args.exclude, include_text=args.include, min_size=min_size_bytes,
                           max_size=max_size_bytes, sort_by_size=args.size, verbose=args.verbose, print_sizes=args.print_sizes)
        total_matches = len(files)
        print(f"\nTotal matches found: {total_matches}")
    except Exception as e:
        print(f"An error occurred: {e}")
        return

    if args.output:
        output_path = Path(args.output).resolve()
        try:
            with open(output_path, 'w') as f:
                for file_path, _ in files:
                    f.write(f"{file_path}\n")
            if args.verbose:
                print(f"Results written to {output_path}")
            print(f"\nOutput file location: {output_path}")
        except IOError as e:
            print(f"Failed to write to output file {output_path}: {e}")

if __name__ == "__main__":
    main()
