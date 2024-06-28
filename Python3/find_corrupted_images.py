#!/usr/bin/env python

import concurrent.futures
import multiprocessing
import os
import subprocess
import sys
from tqdm import tqdm

# Constants
OUTPUT_FILE = "corrupted_images_by_color.txt"
NUM_CPUS = multiprocessing.cpu_count()

def check_imagemagick_installed():
    try:
        subprocess.run(["identify", "-version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    except subprocess.CalledProcessError:
        print("ImageMagick is not installed. Please install ImageMagick to use this script.", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print("ImageMagick is not installed. Please install ImageMagick to use this script.", file=sys.stderr)
        sys.exit(1)

def check_image_validity(image_path):
    try:
        result = subprocess.run(
            ["identify", "-regard-warnings", image_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        if result.returncode != 0:
            return image_path  # Return the path if there's an error
        return None
    except Exception as e:
        return image_path  # Return the path if there's an error

def get_all_jpg_images(directory):
    jpg_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.lower().endswith(".jpg"):
                jpg_files.append(os.path.join(root, file))
    return jpg_files

def main():
    check_imagemagick_installed()
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_file_path = os.path.join(script_dir, OUTPUT_FILE)
    
    print("Starting the image validation process")
    
    # Get all JPG images
    jpg_images = get_all_jpg_images(script_dir)
    print(f"Found {len(jpg_images)} JPG images to validate")
    
    # Create a ThreadPoolExecutor
    with concurrent.futures.ThreadPoolExecutor(max_workers=NUM_CPUS) as executor:
        futures = {executor.submit(check_image_validity, img): img for img in jpg_images}
        
        corrupted_images = []
        for future in tqdm(concurrent.futures.as_completed(futures), total=len(futures), desc="Validating images", unit="image"):
            result = future.result()
            if result:
                corrupted_images.append(result)

    # Sort the corrupted image paths
    corrupted_images.sort()

    # Write the sorted paths to the output file
    with open(output_file_path, 'w') as output_file:
        for image_path in corrupted_images:
            output_file.write(f"{image_path}\n")

    print("Image validation process completed")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Critical error: {e}", file=sys.stderr)
        sys.exit(1)
