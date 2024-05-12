#!/usr/bin/env python3

import os
import sys
import argparse
import subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import tempfile
import shutil

def process_image(image_path, size=None, verbose=False):
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_dir = Path(temp_dir)
            output_file_path = temp_dir / f"{image_path.stem}-IM{image_path.suffix}"

            convert_opts = [
                '-filter', 'Triangle',
                '-define', 'filter:support=2',
                '-strip',
                '-unsharp', '0.25x0.08+8.3+0.045',
                '-dither', 'None',
                '-posterize', '136',
                '-quality', '82',
                '-define', 'jpeg:fancy-upsampling=off',
                '-auto-level',
                '-enhance',
                '-interlace', 'none',
                '-colorspace', 'sRGB'
            ]
            if size:
                convert_opts += ['-resize', size]

            command = ['magick', 'convert', str(image_path)] + convert_opts + [str(output_file_path)]
            subprocess.run(command, check=True)

            shutil.move(str(output_file_path), str(image_path.with_name(f"{image_path.stem}-IM{image_path.suffix}")))
            os.remove(str(image_path))  # Remove the original input file

            if verbose:
                print(f"Processed {image_path} successfully and saved as {image_path.stem}-IM{image_path.suffix}")
            return True
    except subprocess.CalledProcessError as e:
        if verbose:
            print(f"Failed to process {image_path}: {e}")
        return False

def process_images(directory, file_type, size=None, verbose=False, recursive=False, num_threads=None):
    directory = Path(directory)
    if verbose:
        print(f"Processing images in directory with {num_threads} threads: {directory}")

    if not directory.exists():
        print(f"Directory {directory} does not exist.")
        return

    search_pattern = '**/*.' + file_type if recursive else '*.' + file_type
    images = list(directory.rglob(search_pattern)) if recursive else list(directory.glob(search_pattern))
    images = [img for img in images if '-IM' not in img.stem]

    if verbose:
        print(f"Found {len(images)} images of type {file_type} to process.")

    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        future_to_image = {executor.submit(process_image, img, size, verbose): img for img in images}
        
        for future in as_completed(future_to_image):
            image = future_to_image[future]
            success = future.result()
            
            if not success:
                if verbose:
                    print(f"Image {image} failed to process, halving the number of threads and retrying...")
                num_threads = max(1, num_threads // 2)
                process_images(directory, file_type, size, verbose, recursive, num_threads)
                return

def main():
    parser = argparse.ArgumentParser(description="Process images using ImageMagick with dynamic thread adjustment.")
    parser.add_argument('-d', '--dir', type=str, default=os.getcwd(), help='Directory to process images from.')
    parser.add_argument('-t', '--type', type=str, default='jpg', help='File type to process (e.g., jpg, png).')
    parser.add_argument('-s', '--size', type=str, help='Resize images to specified dimensions, e.g., 800x600.')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output.')
    parser.add_argument('-r', '--recursive', action='store_true', help='Enable recursive processing of subdirectories.')
    args = parser.parse_args()

    initial_threads = os.cpu_count()  # Use all available CPUs
    process_images(args.dir, args.type, args.size, args.verbose, args.recursive, initial_threads)

if __name__ == "__main__":
    main()
