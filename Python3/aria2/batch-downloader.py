#!/usr/bin/env python3

import json
import os
import subprocess

def download_video(filename, path, url, extension):
    # Create the download directory if it doesn't exist
    os.makedirs(path, exist_ok=True)

    # Construct the output filename
    output_file = f"{filename}.{extension}"

    # Download the video using aria2c
    subprocess.run(["aria2c", "--conf-path", os.path.expanduser("~/.aria2/aria2.conf"), "--out", output_file, url], cwd=path)

def batch_download_videos(video_data):
    for video in video_data:
        filename = video["filename"]
        path = video["path"]
        url = video["url"]
        extension = video["extension"]

        print(f"Downloading video: {filename}")
        download_video(filename, path, url, extension)

def main():
    # Read the video data from a JSON file
    with open("video_data.json") as file:
        video_data = json.load(file)

    # Batch download the videos
    batch_download_videos(video_data)

    # Provide feedback after all downloads are complete
    subprocess.run(["google_speech", "Batch video download completed."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if __name__ == "__main__":
    main()
