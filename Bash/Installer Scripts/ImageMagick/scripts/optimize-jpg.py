#!/usr/bin/env python3

import os
import subprocess
from pathlib import Path

def find_jpg_files(directory):
    for path in Path(directory).rglob('*.jpg'):
        if '-IM.jpg' not in path.name:
            yield path

def convert_image(image_path):
    output_path = image_path.parent / f"{image_path.stem}-IM.jpg"
    subprocess.run(["convert", str(image_path), str(output_path)])
    os.remove(image_path)

def display_progress_bar(total, progress, filename):
    bar_length = 30
    filled_length = int(bar_length * progress // total)
    bar = '█' * filled_length + '-' * (bar_length - filled_length)
    percent = (progress / total) * 100
    print(f"\rConverted: {filename}\nProgress: |{bar}| {percent:.2f}%", end='\r')

def main():
    directory = '.'  # Current directory
    files = list(find_jpg_files(directory))
    total_files = len(files)

    print("Starting image conversion...")
    for index, file in enumerate(files, start=1):
        convert_image(file)
        display_progress_bar(total_files, index, file.name)

    print("\nImage conversion completed.")

if __name__ == "__main__":
    main()
