#!/usr/bin/env python

import os
import sys
import logging
import concurrent.futures
import multiprocessing
from PIL import Image
from tqdm import tqdm

# Constants
OUTPUT_FILE = "corrupted_images.txt"
LOG_FILE = "scan_images.log"

# Configure logging
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Get the number of logical CPUs
num_cpus = multiprocessing.cpu_count()

# Function to scan a single image
def scan_image(image_path):
    try:
        with Image.open(image_path) as img:
            img.verify()  # Verify the image integrity
        logging.info(f"Successfully scanned image: {image_path}")
        return None  # No error
    except Exception as e:
        logging.error(f"Error scanning image {image_path}: {e}")
        return image_path  # Return the path if there's an error

# Function to recursively get all JPG images
def get_all_jpg_images(directory):
    jpg_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.lower().endswith(".jpg"):
                jpg_files.append(os.path.join(root, file))
    return jpg_files

# Main function
def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_file_path = os.path.join(script_dir, OUTPUT_FILE)
    
    logging.info("Starting the image scanning process")
    
    # Get all JPG images
    jpg_images = get_all_jpg_images(script_dir)
    logging.info(f"Found {len(jpg_images)} JPG images to scan")
    
    # Create a ThreadPoolExecutor
    with concurrent.futures.ThreadPoolExecutor(max_workers=num_cpus) as executor:
        futures = {executor.submit(scan_image, img): img for img in jpg_images}
        
        with open(output_file_path, 'w') as output_file:
            for future in tqdm(concurrent.futures.as_completed(futures), total=len(futures), desc="Scanning images", unit="image"):
                result = future.result()
                if result:  # If there's an error
                    output_file.write(f"{result}\n")
                    logging.error(f"Corrupted image found: {result}")

    logging.info("Image scanning process completed")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.critical(f"Critical error: {e}")
        sys.exit(1)
