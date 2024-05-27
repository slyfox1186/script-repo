#!/usr/bin/env python3
import json
import os
import requests
import sys
import logging

logging.basicConfig(level=logging.INFO, format='%(message)s')

def create_json_entry(filename, path, url):
    entry = {
        "filename": filename,
        "path": path,
        "url": url,
        "extension": filename.split('.')[-1]
    }
    return entry

def create_json_file(output_file, filename, path, url):
    logging.info("Creating JSON entry")
    entry = create_json_entry(filename, path, url)

    try:
        with open(output_file, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        data = []

    if entry in data:
        logging.info(f"Entry already exists in {output_file}. Skipping adding.")
    else:
        data.append(entry)
        with open(output_file, 'w') as f:
            json.dump(data, f, indent=4)
        logging.info(f"Entry added to {output_file}")

def download_file(url, save_path):
    try:
        logging.info(f"Downloading {url} to {save_path}")
        response = requests.get(url)
        response.raise_for_status()
        with open(save_path, 'wb') as file:
            file.write(response.content)
        logging.info(f"Downloaded {url} successfully")
    except requests.RequestException as e:
        logging.error(f"Failed to download {url}: {e}")

def batch_download_from_json(json_file):
    try:
        with open(json_file, 'r') as file:
            files = json.load(file)
        logging.info(f"Loaded JSON file: {json_file}")
    except FileNotFoundError:
        logging.error(f"JSON file not found: {json_file}")
        return

    for file_info in files:
        url = file_info["url"]
        file_name = file_info["filename"]
        output_dir = file_info["path"]

        if not os.path.exists(output_dir):
            logging.info(f"Creating directory: {output_dir}")
            os.makedirs(output_dir)

        save_path = os.path.join(output_dir, file_name)
        download_file(url, save_path)

if __name__ == "__main__":
    import argparse
    script_name = os.path.basename(sys.argv[0])
    parser = argparse.ArgumentParser(description=f"""
Utility script for creating JSON file entries and batch downloading files from a JSON file.

Commands:
    json            Create a JSON entry with provided filename, path, and URL.
    batch           Batch download files from a JSON file.

Examples:
    Create a JSON entry:
        {script_name} json <filename> <path> <url>

    Batch download files from a JSON file:
        {script_name} batch <json_file>
    """, formatter_class=argparse.RawTextHelpFormatter)

    subparsers = parser.add_subparsers(dest='command', required=True)

    json_parser = subparsers.add_parser('json', help="Create a JSON entry with provided filename, path, and URL")
    json_parser.add_argument("filename", help="Filename of the file")
    json_parser.add_argument("path", help="Path to the file")
    json_parser.add_argument("url", help="URL for downloading the file")

    batch_parser = subparsers.add_parser('batch', help="Batch download files from a JSON file")
    batch_parser.add_argument("json_file", help="Path to the JSON file containing download information")

    args = parser.parse_args()

    if args.command == 'json':
        if not args.filename or not args.path or not args.url:
            parser.error("The 'json' command requires <filename>, <path>, and <url> arguments.")
        create_json_file("download.json", args.filename, args.path, args.url)
        logging.info("JSON creation process completed")
    elif args.command == 'batch':
        if not args.json_file:
            parser.error("The 'batch' command requires <json_file> argument.")
        batch_download_from_json(args.json_file)
        logging.info("Batch download process completed")
