#!/usr/bin/env python3

import os
import argparse
import concurrent.futures
from PIL import Image

def process_image(file_path, min_width, min_height, verbose):
    try:
        with Image.open(file_path) as img:
            width, height = img.size
            if verbose:
                print(f"Processing image: {file_path} ({width}x{height})")
            return file_path, width, height
    except Exception as e:
        if verbose:
            print(f"Error processing image {file_path}: {str(e)}")
    return None

def find_top_images(directory, max_results, min_width, min_height, top_width, top_height, verbose):
    image_data = []
    processed_count = 0

    if verbose:
        print("Script started.")
        print("Searching for JPG files recursively in the specified directory and its subdirectories...")

    with concurrent.futures.ThreadPoolExecutor() as executor:
        futures = []
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file.lower().endswith((".jpg", ".jpeg")):
                    file_path = os.path.join(root, file)
                    futures.append(executor.submit(process_image, file_path, min_width, min_height, verbose))
                    processed_count += 1

                    if max_results >= 0 and processed_count >= max_results:
                        if verbose:
                            print("Reached maximum number of images to search. Stopping search.")
                        break

            if max_results >= 0 and processed_count >= max_results:
                break

        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                image_data.append(result)

    if verbose:
        print(f"Processed {processed_count} JPG files.")
        print("Processing images...")

    image_data.sort(key=lambda x: x[1], reverse=True)
    width_matches = [img for img in image_data if img[1] >= min_width][:top_width]
    if not width_matches:
        print(f"No images found with width greater than or equal to {min_width}.")
        print(f"Returning the top {top_width} largest images by width:")
        width_matches = image_data[:top_width]
    for file_path, width, height in width_matches:
        print(f"{file_path}: {width} x {height}")

    print()

    image_data.sort(key=lambda x: x[2], reverse=True)
    height_matches = [img for img in image_data if img[2] >= min_height][:top_height]
    if not height_matches:
        print(f"No images found with height greater than or equal to {min_height}.")
        print(f"Returning the top {top_height} largest images by height:")
        height_matches = image_data[:top_height]
    for file_path, width, height in height_matches:
        print(f"{file_path}: {width} x {height}")

    if verbose:
        print("Script finished.")

def main():
    parser = argparse.ArgumentParser(description="Find Top Images by Width and Height")
    parser.add_argument("-d", "--directory", default=".", help="Directory to search for images (default: current directory)")
    parser.add_argument("-m", "--max-results", type=int, default=-1, help="Maximum number of images to search (optional)")
    parser.add_argument("-w", "--min-width", type=int, default=0, help="Minimum width for a valid match (optional, default: 0)")
    parser.add_argument("-e", "--min-height", type=int, default=0, help="Minimum height for a valid match (optional, default: 0)")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose logging")
    parser.add_argument("top_width", type=int, help="Number of top results for width")
    parser.add_argument("top_height", type=int, help="Number of top results for height")

    args = parser.parse_args()

    find_top_images(args.directory, args.max_results, args.min_width, args.min_height, args.top_width, args.top_height, args.verbose)

if __name__ == "__main__":
    main()
