#!/usr/bin/env python3

# WARNING: this WILL overwrite the original images!
# You have been warned!

import os
import subprocess
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed
import time

def find_jpg_files(directory):
    for path in Path(directory).rglob('*.jpg'):
        if '-IM.jpg' not in path.name:
            yield path

def convert_image(image_path):
    output_path = image_path.parent / f"{image_path.stem}-IM.jpg"
    # Suppress all output from the convert command
    with open(os.devnull, 'wb') as devnull:
        subprocess.run([
            "convert", str(image_path),
            "-filter", "Triangle",
            "-define", "filter:support=2",
            "-thumbnail", "100%",
            "-strip",
            "-unsharp", "0.25x0.08+8.3+0.045",
            "-dither", "None",
            "-posterize", "136",
            "-quality", "82",
            "-define", "jpeg:fancy-upsampling=off",
            "-auto-level",
            "-enhance",
            "-interlace", "none",
            "-colorspace", "sRGB",
            str(output_path)
        ], stdout=devnull, stderr=devnull)
    os.remove(image_path)
    return image_path.name

def main():
    directory = '.'  # Current directory
    files = list(find_jpg_files(directory))
    total_files = len(files)

    print("Starting image conversion...")

    with ProcessPoolExecutor() as executor:
        future_to_file = {executor.submit(convert_image, file): file for file in files}

        for index, future in enumerate(as_completed(future_to_file), start=1):
            filename = future_to_file[future]
            try:
                result = future.result()
                print(f"Converted: {result}")
            except Exception as e:
                print(f"Error converting file {filename}: {e}")

            # Stagger file processing to reduce I/O load
            time.sleep(0.5)  # Adjust the sleep time as needed

            # Update progress bar
            bar_length = 30
            filled_length = int(bar_length * index // total_files)
            bar = '█' * filled_length + '-' * (bar_length - filled_length)
            percent = (index / total_files) * 100
            print(f"\rProgress: |{bar}| {percent:.2f}%", end='\r')

    print("\nImage conversion completed.")

if __name__ == "__main__":
    main()
