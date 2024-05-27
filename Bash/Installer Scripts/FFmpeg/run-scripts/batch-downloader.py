#!/usr/bin/env python3

import json
import os
import subprocess
import sys
import logging

logging.basicConfig(level=logging.INFO, format='%(message)s')

def create_json_entry(filename, path, url):
    entry = {
        "filename": filename,
        "path": path,
        "url": url,
        "extension": filename.split('.')[-1] if '.' in filename else ""
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

def download_video(filename, path, url):
    # Create the download directory if it doesn't exist
    os.makedirs(path, exist_ok=True)

    # Construct the output filename
    output_file = filename

    # Download the video using aria2c
    try:
        logging.info(f"URL: {url}")
        logging.info(f"Path: {os.path.join(path, output_file)}")
        subprocess.run(["aria2c", "--conf-path", os.path.expanduser("~/.aria2/aria2.conf"), "--out", output_file, url], cwd=path, check=True)
        logging.info(f"Downloaded {url} successfully")
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to download {url}: {e}")

def batch_download_videos(video_data):
    for video in video_data:
        filename = video["filename"]
        path = video["path"]
        url = video["url"]

        download_video(filename, path, url)

def batch_download_from_json(json_file):
    try:
        with open(json_file, 'r') as file:
            video_data = json.load(file)
        logging.info(f"Loaded JSON file: {json_file}")
    except FileNotFoundError:
        logging.error(f"JSON file not found: {json_file}")
        return

    batch_download_videos(video_data)
    subprocess.run(["google_speech", "Batch video download completed."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

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
