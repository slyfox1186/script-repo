#!/usr/bin/env python3

# WARNING this WILL overwrite the original images!
# You have been warned!

import os
import subprocess
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed

def find_jpg_files(directory):
    for path in Path(directory).rglob('*.jpg'):
        if '-IM.jpg' not in path.name:
            yield path

def convert_image(image_path):
    output_path = image_path.parent / f"{image_path.stem}-IM.jpg"
    subprocess.run(["convert", str(image_path), str(output_path)])
    os.remove(image_path)
    return image_path.name

def main():
    directory = '.'  # Current directory
    files = list(find_jpg_files(directory))
    total_files = len(files)

    print("Starting image conversion...")

    with ProcessPoolExecutor() as executor:
        # Map the convert_image function to the files
        future_to_file = {executor.submit(convert_image, file): file for file in files}
        
        for index, future in enumerate(as_completed(future_to_file), start=1):
            filename = future_to_file[future]
            try:
                result = future.result()
                print(f"Converted: {result}")
            except Exception as e:
                print(f"Error converting file {filename}: {e}")

            # Update progress bar
            bar_length = 30
            filled_length = int(bar_length * index // total_files)
            bar = '█' * filled_length + '-' * (bar_length - filled_length)
            percent = (index / total_files) * 100
            print(f"\rProgress: |{bar}| {percent:.2f}%", end='\r')

    print("\nImage conversion completed.")

if __name__ == "__main__":
    main()
