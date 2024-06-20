#!/usr/bin/env python3

import os
import sys
import argparse
import ffmpeg
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

def search_file(file_path, search_terms):
    matches = []
    try:
        file_name = os.path.basename(file_path)
        if any(term in file_name.lower() for term in search_terms):
            matches.append(f"Found in file name: {file_path}")
        else:
            metadata = ffmpeg.probe(file_path, show_entries='format_tags=*')
            if any(term in str(metadata['format']['tags']).lower() for term in search_terms):
                matches.append(f"Found in metadata: {file_path}")
    except ffmpeg.Error as e:
        logging.error(f"Error processing file: {file_path}")
        logging.error(f"Error message: {e.stderr}")
    except Exception as e:
        logging.error(f"Error processing file: {file_path}")
        logging.error(f"Error message: {str(e)}")
    return matches

def search_files(directory, search_terms, output_file, max_workers=4):
    mp4_files = [os.path.join(root, file) for root, dirs, files in os.walk(directory) for file in files if file.endswith(".mp4")]

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(search_file, file_path, search_terms) for file_path in mp4_files]
        matches = []
        with tqdm(total=len(mp4_files), desc='Processing files', unit='file') as progress_bar:
            for future in as_completed(futures):
                matches.extend(future.result())
                progress_bar.update(1)

    if output_file:
        try:
            with open(output_file, 'w') as file:
                file.write('\n'.join(matches))
            logging.info(f"Search results saved to: {output_file}")
        except IOError as e:
            logging.error(f"Error writing to output file: {output_file}")
            logging.error(f"Error message: {str(e)}")
    else:
        print('\n'.join(matches))

def main():
    parser = argparse.ArgumentParser(description='Search for words in .mp4 file names and metadata.')
    parser.add_argument('search_terms', metavar='search_terms', type=str,
                        help='comma-separated list of words to search for')
    parser.add_argument('-o', '--output', metavar='output_file', type=str,
                        help='path to the output file (optional)')
    parser.add_argument('-t', '--threads', metavar='max_workers', type=int, default=4,
                        help='maximum number of worker threads (default: 4)')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='enable verbose logging')
    args = parser.parse_args()

    if args.verbose:
        logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
    else:
        logging.basicConfig(level=logging.ERROR, format='%(levelname)s: %(message)s')

    search_terms = [term.strip().lower() for term in args.search_terms.split(',')]
    current_directory = os.path.dirname(os.path.abspath(__file__))

    search_files(current_directory, search_terms, args.output, args.threads)

if __name__ == '__main__':
    main()
