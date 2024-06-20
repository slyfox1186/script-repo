#!/usr/bin/env python3

import os
import argparse
import logging
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed

def setup_logging(log_file=None, verbose=False):
    log_level = logging.DEBUG if verbose else logging.INFO
    log_format = '%(asctime)s - %(levelname)s - %(message)s'

    handlers = [logging.StreamHandler()]
    if log_file:
        handlers.append(logging.FileHandler(log_file, mode='w'))

    logging.basicConfig(level=log_level, format=log_format, handlers=handlers)
    logger = logging.getLogger()
    return logger

def get_dir_tree(root_dir, logger):
    dir_tree = {}
    try:
        for dirpath, dirnames, filenames in tqdm(os.walk(root_dir), desc=f"Scanning {root_dir}", unit="dirs", leave=False):
            # Create a relative path for each directory
            rel_path = os.path.relpath(dirpath, root_dir)
            if rel_path == '.':
                rel_path = ''
            # Add directories to the tree structure
            dir_tree[rel_path] = set(dirnames)
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug(f"Scanned directory: {dirpath}, subdirectories: {dirnames}")
    except Exception as e:
        logger.error(f"Error while scanning directory {root_dir}: {e}")
    return dir_tree

def compare_dir_trees(tree1, tree2):
    common_dirs = []
    for dir1, subdirs1 in tree1.items():
        if dir1 in tree2 and subdirs1 == tree2[dir1]:
            common_dirs.append((dir1, dir1))
    return common_dirs

def scan_directory(directory, logger):
    logger.info(f"Scanning directory: {directory}")
    return get_dir_tree(directory, logger)

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def main():
    parser = argparse.ArgumentParser(description='Compare directory structures of two folders.')
    parser.add_argument('dir1', type=str, help='First directory to compare')
    parser.add_argument('dir2', type=str, help='Second directory to compare')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    parser.add_argument('-l', '--log', type=str, help='Output log file (relative or full path)')
    args = parser.parse_args()

    logger = setup_logging(args.log, args.verbose)

    if not os.path.isdir(args.dir1):
        logger.error(f"First input is not a valid directory: {args.dir1}")
        return

    if not os.path.isdir(args.dir2):
        logger.error(f"Second input is not a valid directory: {args.dir2}")
        return

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = {executor.submit(scan_directory, args.dir1, logger): 'dir1', executor.submit(scan_directory, args.dir2, logger): 'dir2'}
        results = {}
        for future in as_completed(futures):
            dir_name = futures[future]
            try:
                results[dir_name] = future.result()
            except Exception as e:
                logger.error(f"Error processing {dir_name}: {e}")

    tree1 = results.get('dir1')
    tree2 = results.get('dir2')

    if tree1 and tree2:
        logger.info("Comparing directory trees...")
        common_dirs = compare_dir_trees(tree1, tree2)

        clear_screen()

        if common_dirs:
            print("Common directories with similar structure:")
            for dir1, dir2 in common_dirs:
                print(f"{args.dir1}/{dir1} <-> {args.dir2}/{dir2}")
        else:
            print("No common directories with similar structure found.")

if __name__ == '__main__':
    main()
