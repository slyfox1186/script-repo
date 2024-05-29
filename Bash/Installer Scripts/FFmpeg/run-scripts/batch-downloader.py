#!/usr/bin/env python3

import json
import os
import subprocess
import sys
import logging
import tempfile
import shutil
import argparse
import hashlib
import time
from configparser import ConfigParser

logging.basicConfig(level=logging.INFO, format='%(message)s')

LAST_JSON_PATH_FILE = "last_json_path.txt"
CONFIG_FILE = "batch-downloader-config.ini"

def load_config(config_file):
    config = ConfigParser()
    if os.path.exists(config_file):
        config.read(config_file)
    return config

def create_example_config(file_path):
    config = ConfigParser()
    config['default'] = {
        'default_download_directory': '/path/to/default/download/directory',
        'log_file_path': '/path/to/default/log/file.log',
        'verbose': 'True',
        'retry_count': '3',
        'aria2c_conf_path': '~/.aria2/aria2.conf',
        'checksum_algorithm': 'sha256',
        'google_speech_enabled': 'True'
    }
    with open(file_path, 'w') as configfile:
        config.write(configfile)
    print(f"Example config file created at {file_path}")

def create_json_entry(filename, path, url):
    return {
        "filename": filename,
        "path": path,
        "url": url
    }

def create_json_file(filename, path, url):
    output_file = "download.json"
    
    try:
        with open(output_file, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        data = []

    entry = create_json_entry(filename, path, url)

    if entry in data:
        logging.info(f"Entry already exists in {output_file}. Skipping adding.")
        subprocess.run(["google_speech", f"Entry for {filename} already exists. Skipping adding."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        data.append(entry)
        with open(output_file, 'w') as f:
            json.dump(data, f, indent=4)
        logging.info(f"Entry added to {output_file}")
        subprocess.run(["google_speech", f"Entry for {filename} added successfully."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    with open(LAST_JSON_PATH_FILE, 'w') as path_file:
        path_file.write(os.path.abspath(output_file))

def get_file_checksum(file_path, algorithm='sha256'):
    hash_algo = hashlib.new(algorithm)
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            hash_algo.update(chunk)
    return hash_algo.hexdigest()

def verify_download(filename, path, expected_checksum, verbose):
    file_path = os.path.join(path, filename)
    if not os.path.exists(file_path):
        logging.error(f"File {filename} not found for verification.")
        return False

    actual_checksum = get_file_checksum(file_path)
    if actual_checksum != expected_checksum:
        logging.error(f"Checksum mismatch for {filename}. Expected: {expected_checksum}, Actual: {actual_checksum}")
        subprocess.run(["google_speech", f"Checksum mismatch for {filename}."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return False

    if verbose:
        logging.info(f"Checksum verification passed for {filename}.")
    return True

def download_video(filename, path, url, retries, verbose, aria2c_conf_path):
    aria2c_conf_path = os.path.expanduser(aria2c_conf_path)

    os.makedirs(path, exist_ok=True)
    output_file = filename

    for attempt in range(retries):
        try:
            logging.info(f"URL: {url}")
            logging.info(f"Path: {os.path.join(path, output_file)}")
            result = subprocess.run(
                ["aria2c", "--conf-path", aria2c_conf_path, "--out", output_file, url],
                cwd=path, check=True
            )
            logging.info(f"Downloaded {url} successfully")
            subprocess.run(["google_speech", f"Downloaded {filename} successfully."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except subprocess.CalledProcessError as e:
            logging.error(f"Failed to download {url} (Attempt {attempt + 1}/{retries}): {e}")
            if attempt < retries - 1:
                logging.info("Retrying...")
            subprocess.run(["google_speech", f"Failed to download {filename}. Retrying..."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    logging.error(f"Failed to download {url} after {retries} attempts.")
    return False

def batch_download_videos(video_data, verbose, retries, aria2c_conf_path, filter_criteria=None, checksum_algorithm='sha256', google_speech_enabled=True):
    success_count = 0
    failure_count = 0
    total_size = 0
    start_time = time.time()
    
    for video in video_data:
        filename = video["filename"]
        path = video["path"]
        url = video["url"]
        expected_checksum = video.get("checksum", "")

        if filter_criteria and not filter_criteria(filename, path, url):
            continue

        if download_video(filename, path, url, retries, verbose, aria2c_conf_path):
            if expected_checksum and not verify_download(filename, path, expected_checksum, verbose):
                failure_count += 1
                continue
            success_count += 1
            total_size += os.path.getsize(os.path.join(path, filename))
        else:
            failure_count += 1
    
    end_time = time.time()
    elapsed_time = end_time - start_time
    logging.info(f"Batch download completed with {success_count} successes and {failure_count} failures.")
    logging.info(f"Total size downloaded: {total_size / (1024 * 1024):.2f} MB")
    logging.info(f"Time taken: {elapsed_time:.2f} seconds")
    if google_speech_enabled:
        subprocess.run(["google_speech", f"Batch download completed with {success_count} successes and {failure_count} failures."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def batch_download_from_json(json_file, verbose, retries, aria2c_conf_path, filter_criteria=None, checksum_algorithm='sha256', google_speech_enabled=True):
    try:
        with open(json_file, 'r') as file:
            video_data = json.load(file)
        logging.info(f"Loaded JSON file: {json_file}")
    except FileNotFoundError:
        logging.error(f"JSON file not found: {json_file}")
        if google_speech_enabled:
            subprocess.run(["google_speech", f"JSON file {json_file} not found."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return

    batch_download_videos(video_data, verbose, retries, aria2c_conf_path, filter_criteria=filter_criteria, checksum_algorithm=checksum_algorithm, google_speech_enabled=google_speech_enabled)

def prompt_run_batch(verbose, retries, aria2c_conf_path, checksum_algorithm, google_speech_enabled):
    user_input = input("Do you want to run the batch command now? (yes/no): ").strip().lower()
    if user_input in ["yes", "y"]:
        batch_download_from_json("download.json", verbose, retries, aria2c_conf_path, checksum_algorithm=checksum_algorithm, google_speech_enabled=google_speech_enabled)
        logging.info("Batch download process completed")

def find_json_path():
    try:
        with open(LAST_JSON_PATH_FILE, 'r') as path_file:
            last_path = path_file.read().strip()
            if last_path:
                print(f"Last known download.json location: {last_path}")
                return
    except FileNotFoundError:
        pass
    print("No previous download.json path found.")

def create_template():
    template_content = """\
./batch-downloader.py json <filename> <path> <url>
./batch-downloader.py json "" "" ""
./batch-downloader.py json "" "" ""
./batch-downloader.py json "" "" ""
./batch-downloader.py json "" "" ""
./batch-downloader.py batch download.json
"""
    template_file = "batch-downloader-template.txt"
    with open(template_file, 'w') as f:
        f.write(template_content)
    print(f"Template file {template_file} created successfully.")

def check_requirements():
    try:
        subprocess.run(["aria2c", "--version"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        logging.error("aria2c is not installed. Please install it to use this script.")
        sys.exit(1)

def interactive_mode(verbose, retries, aria2c_conf_path, checksum_algorithm, google_speech_enabled):
    if os.path.exists("download.json"):
        user_input = input("download.json file exists. Do you want to delete it? (yes/no): ").strip().lower()
        if user_input in ["yes", "y"]:
            os.remove("download.json")
            logging.info("Deleted existing download.json file")

    while True:
        filename = input("Enter filename (or 'done' to finish): ")
        if filename.lower() == 'done':
            break
        path = input("Enter path: ")
        url = input("Enter URL: ")
        create_json_file(filename, path, url)
    
    prompt_run_batch(verbose, retries, aria2c_conf_path, checksum_algorithm, google_speech_enabled)

def main():
    config = load_config(CONFIG_FILE)
    
    script_name = os.path.basename(sys.argv[0])
    parser = argparse.ArgumentParser(description=f"""
Utility script for creating JSON file entries and batch downloading files from a JSON file.

Commands:
    json            Create a JSON entry with provided filename, path, and URL.
    batch           Batch download files from a JSON file.
    find-json       Display the last known location of download.json.
    template        Create a template file for batch commands.
    interactive     Enter interactive mode to add download details one by one.

Examples:
    Create a JSON entry:
        {script_name} json <filename> <path> <url>

    Batch download files from a JSON file:
        {script_name} batch download.json

    Find the last known download.json location:
        {script_name} -f

    Create a template file:
        {script_name} -t
    """, formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument("-f", "--find-json", action="store_true", help="Display the last known location of download.json")
    parser.add_argument("-t", "--template", action="store_true", help="Create a template file for batch commands")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose logging")
    parser.add_argument("--config", type=str, default=CONFIG_FILE, help="Specify a configuration file")
    parser.add_argument("--log-file", type=str, help="Specify a log file path")
    parser.add_argument("--retries", type=int, default=config.getint('default', 'retry_count', fallback=3), help="Specify the number of retries for failed downloads")
    parser.add_argument("--aria2c-conf-path", type=str, default=config.get('default', 'aria2c_conf_path', fallback="~/.aria2/aria2.conf"), help="Specify the aria2c configuration file path")
    parser.add_argument("--checksum-algorithm", type=str, default=config.get('default', 'checksum_algorithm', fallback='sha256'), help="Specify the checksum algorithm for download verification")
    parser.add_argument("--google-speech-enabled", type=bool, default=config.getboolean('default', 'google_speech_enabled', fallback=True), help="Enable or disable Google speech notifications")
    parser.add_argument("--create-config", action="store_true", help="Create an example configuration file")

    subparsers = parser.add_subparsers(dest='command')

    json_parser = subparsers.add_parser('json', help="Create a JSON entry with provided filename, path, and URL")
    json_parser.add_argument("filename", help="Filename of the file")
    json_parser.add_argument("path", help="Path to the file")
    json_parser.add_argument("url", help="URL for downloading the file")

    batch_parser = subparsers.add_parser('batch', help="Batch download files from a JSON file")
    batch_parser.add_argument("json_file", help="Path to the JSON file containing download information")
    batch_parser.add_argument("--filter", type=str, help="Filter files to download based on a filename pattern")

    interactive_parser = subparsers.add_parser('interactive', help="Enter interactive mode to add download details one by one")

    args = parser.parse_args()

    if args.create_config:
        create_example_config('batch-downloader.conf')
        sys.exit(0)

    if args.log_file:
        logging.basicConfig(filename=args.log_file, level=logging.DEBUG if args.verbose else logging.INFO, format='%(asctime)s - %(message)s')

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    check_requirements()

    if args.find_json:
        find_json_path()
    elif args.template:
        create_template()
    elif args.command == 'json':
        if not args.filename or not args.path or not args.url:
            parser.error("The 'json' command requires <filename>, <path>, and <url> arguments.")
        create_json_file(args.filename, args.path, args.url)
        logging.info("JSON creation process completed")
    elif args.command == 'batch':
        def filter_criteria(filename, path, url):
            return args.filter in filename if args.filter else True

        batch_download_from_json(args.json_file, verbose=args.verbose, retries=args.retries, aria2c_conf_path=args.aria2c_conf_path, filter_criteria=filter_criteria, checksum_algorithm=args.checksum_algorithm, google_speech_enabled=args.google_speech_enabled)
        logging.info("Batch download process completed")
    elif args.command == 'interactive':
        interactive_mode(args.verbose, args.retries, args.aria2c_conf_path, args.checksum_algorithm, args.google_speech_enabled)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
