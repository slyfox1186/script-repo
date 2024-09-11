#!/usr/bin/env python3

import sys
import os
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
from functools import partial
import multiprocessing
from fuzzywuzzy import fuzz
from Levenshtein import distance as levenshtein_distance
import argparse
from tqdm import tqdm
import logging
import json
import csv
import tempfile

def similar(a, b, fuzzy_threshold, levenshtein_threshold):
    a_lower, b_lower = a.lower(), b.lower()
    fuzzy_ratio = fuzz.ratio(a_lower, b_lower)
    lev_distance = levenshtein_distance(a_lower, b_lower)
    return fuzzy_ratio >= fuzzy_threshold or lev_distance <= levenshtein_threshold

def find_similar_items(root, names, targets, fuzzy_threshold, levenshtein_threshold, file_types):
    matches = []
    matched_targets = set()
    for name in names:
        full_path = os.path.join(root, name)
        is_dir = os.path.isdir(full_path)
        if file_types:
            if 'folder' in file_types and is_dir:
                pass
            elif not is_dir and not any(name.lower().endswith(ft.lower()) for ft in file_types if ft != 'folder'):
                continue
        for target in targets:
            if similar(name, target, fuzzy_threshold, levenshtein_threshold):
                matches.append((full_path, target))
                matched_targets.add(target)
                break
    return matches, matched_targets

def process_directory(args):
    root, dirs, files, targets, fuzzy_threshold, levenshtein_threshold, file_types = args
    return find_similar_items(root, dirs + files, targets, fuzzy_threshold, levenshtein_threshold, file_types)

def find_similar_files(search_dir, target_names, max_workers, fuzzy_threshold, levenshtein_threshold, file_types):
    matches = []
    all_matched_targets = set()
    total_items = sum([len(files) + len(dirs) for _, dirs, files in os.walk(search_dir)])
    
    with ProcessPoolExecutor(max_workers=max_workers) as executor:
        walker = os.walk(search_dir)
        tasks = ((root, dirs, files, target_names, fuzzy_threshold, levenshtein_threshold, file_types) 
                 for root, dirs, files in walker)
        
        with tqdm(total=total_items, desc="Searching", unit="item") as pbar:
            for result, matched_targets in executor.map(process_directory, tasks):
                matches.extend(result)
                all_matched_targets.update(matched_targets)
                pbar.update(len(result))
    
    return matches, all_matched_targets

def setup_logging(log_file):
    try:
        logging.basicConfig(filename=log_file, level=logging.INFO,
                            format='%(asctime)s - %(levelname)s - %(message)s')
    except PermissionError:
        temp_dir = tempfile.gettempdir()
        fallback_log = os.path.join(temp_dir, 'find_folders.log')
        print(f"Warning: Cannot write to {log_file}. Using {fallback_log} instead.")
        logging.basicConfig(filename=fallback_log, level=logging.INFO,
                            format='%(asctime)s - %(levelname)s - %(message)s')

def write_output(matches, output_format, output_file):
    try:
        if output_format == 'txt':
            with open(output_file, 'w', encoding='utf-8') as f:
                for match, _ in matches:
                    f.write(f"{match}\n")
        elif output_format == 'json':
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump([match for match, _ in matches], f, indent=2)
        elif output_format == 'csv':
            with open(output_file, 'w', newline='', encoding='utf-8') as f:
                writer = csv.writer(f)
                writer.writerow(['Matched Path'])
                for match, _ in matches:
                    writer.writerow([match])
        print(f"Results written to {output_file}")
    except PermissionError:
        print(f"Error: Permission denied when writing to {output_file}. Printing results to console instead.")
        for match, _ in matches:
            print(match)

def update_input_file(input_file, matched_targets):
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    with open(input_file, 'w', encoding='utf-8') as f:
        for line in lines:
            if line.strip() not in matched_targets:
                f.write(line)

def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Find similar files and folders based on names provided in an input file.",
        epilog="""
Examples:
  python find_folders.py names.txt /path/to/search
  python find_folders.py names.txt /path/to/search --file-types .txt .pdf folder --output-format json --output-file results.json
  python find_folders.py names.txt /path/to/search --fuzzy-threshold 90 --levenshtein-threshold 1

For more information, visit: https://github.com/your-repo/find_folders
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument("input_file", 
                        help="Path to the input text file containing names to search for, one per line")
    parser.add_argument("search_dir", 
                        help="Directory to search recursively for matching files and folders")
    parser.add_argument("--fuzzy-threshold", type=int, default=80, 
                        help="Fuzzy matching threshold (0-100). Higher values require closer matches. Default: 80")
    parser.add_argument("--levenshtein-threshold", type=int, default=2, 
                        help="Levenshtein distance threshold. Lower values require closer matches. Default: 2")
    parser.add_argument("--file-types", nargs='+', 
                        help="File types to search for (e.g., .txt .pdf folder). Use 'folder' to include directories. If not specified, all types are searched")
    parser.add_argument("--output-format", choices=['txt', 'json', 'csv'], default='txt', 
                        help="Output format for results. Default: txt")
    parser.add_argument("--output-file", 
                        help="Path to save the output file. If not specified, results are printed to console")
    parser.add_argument("--log-file", default="find_folders.log", 
                        help="Path to save the log file. Default: find_folders.log")
    parser.add_argument('--version', action='version', version='%(prog)s 1.0')

    return parser.parse_args()

def main():
    args = parse_arguments()

    setup_logging(args.log_file)
    logging.info(f"Starting search with arguments: {args}")

    input_file = Path(args.input_file)
    search_dir = Path(args.search_dir)

    if not input_file.is_file():
        logging.error(f"File '{input_file}' not found.")
        print(f"Error: File '{input_file}' not found.")
        sys.exit(1)

    if not search_dir.is_dir():
        logging.error(f"Directory '{search_dir}' not found.")
        print(f"Error: Directory '{search_dir}' not found.")
        sys.exit(1)

    try:
        with input_file.open('r', encoding='utf-8') as f:
            target_names = [line.strip() for line in f if line.strip()]
    except IOError as e:
        logging.error(f"Error reading file '{input_file}': {e}")
        print(f"Error reading file '{input_file}': {e}")
        sys.exit(1)

    max_workers = max(1, multiprocessing.cpu_count() // 2)
    
    try:
        matches, matched_targets = find_similar_files(search_dir, target_names, max_workers, 
                                     args.fuzzy_threshold, args.levenshtein_threshold, args.file_types)
    except Exception as e:
        logging.error(f"An error occurred while searching: {e}")
        print(f"An error occurred while searching: {e}")
        sys.exit(1)

    if matches:
        print(f"Found {len(matches)} matching files and folders.")
        if args.output_file:
            write_output(sorted(set(matches)), args.output_format, args.output_file)
        else:
            print("Matching files and folders:")
            for match, _ in sorted(set(matches)):
                print(match)
        
        # Update input file
        update_input_file(args.input_file, matched_targets)
        print(f"Updated input file '{args.input_file}' by removing matched entries.")
    else:
        print("No matches found.")

    logging.info(f"Search completed. Found {len(matches)} matches.")

if __name__ == "__main__":
    main()
