#!/usr/bin/env python3

import argparse
import concurrent.futures
import glob
import logging
import os
import subprocess
import sys
import tempfile
from functools import partial
from pathlib import Path
from typing import List, Optional

# Constants
MAX_THREADS = 32

MAGICK_LIMITS = {
    'MAGICK_AREA_LIMIT': '1GP',
    'MAGICK_DISK_LIMIT': '128GiB',
    'MAGICK_FILE_LIMIT': '1536',
    'MAGICK_HEIGHT_LIMIT': '512MP',
    'MAGICK_MAP_LIMIT': '32GiB',
    'MAGICK_MEMORY_LIMIT': '32GiB',
    'MAGICK_THREAD_LIMIT': str(MAX_THREADS),
    'MAGICK_WIDTH_LIMIT': '512MP'
}

os.environ.update(MAGICK_LIMITS)

# Argument parser
def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description='Optimize JPG images.')
    parser.add_argument('-d', '--dir', type=Path, default=Path.cwd(),
                        help='Specify the working directory where images are located.')
    parser.add_argument('-o', '--overwrite', action='store_true',
                        help='Enable overwrite mode. Original images will be overwritten.')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Enable verbose output.')
    parser.add_argument('-t', '--threads', type=int, default=MAX_THREADS,
                        help='Specify the maximum number of threads to use.')
    return parser.parse_args()

# Logging configuration
logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

# Image processing function
def process_image(infile: Path, overwrite_mode: bool, verbose_mode: bool) -> None:
    """Process a single image file."""
    if infile.name.endswith('-IM.jpg') or infile.name.endswith('-IM.jpeg'):
        logger.info(f"Skipped: {infile}")
        return

    base_name = infile.stem
    with tempfile.TemporaryDirectory() as temp_dir:
        mpc_file = Path(temp_dir) / f"{base_name}.mpc"
        outfile = infile.with_name(f"{base_name}-IM.jpg")

        convert_base_opts = [
            '-filter', 'Triangle', '-define', 'filter:support=2',
            '-thumbnail', subprocess.check_output(['identify', '-ping',
            '-format', '%wx%h', str(infile)]).decode('utf-8').strip(),
            '-strip', '-unsharp', '0.25x0.08+8.3+0.045', '-dither', 'None',
            '-posterize', '136', '-quality', '82', '-define', 'jpeg:fancy-upsampling=off',
            '-auto-level', '-enhance', '-interlace', 'none', '-colorspace', 'sRGB'
        ]

        try:
            subprocess.run(['convert', str(infile)] + convert_base_opts +
                           ['-sampling-factor', '2x2', '-limit', 'area', '0', str(mpc_file)],
                           check=True)
        except subprocess.CalledProcessError:
            if verbose_mode:
                logger.warning(f"First attempt failed for {infile}, retrying without '-sampling-factor 2x2 -limit area 0'...")
            try:
                subprocess.run(['convert', str(infile)] + convert_base_opts + [str(mpc_file)], check=True)
            except subprocess.CalledProcessError:
                logger.error(f"Error: Second attempt failed for {infile} as well.")
                return

        try:
            subprocess.run(['convert', str(mpc_file), str(outfile)], check=True)
            logger.info(f"Processed: {outfile}")
        except subprocess.CalledProcessError:
            logger.error(f"Failed to process: {outfile}")

        if overwrite_mode:
            infile.unlink()

# Function to check if google_speech is installed and send notification
def notify_completion() -> bool:
    """Check if google_speech is installed and send notification."""
    try:
        import google_speech
        subprocess.run(['google_speech', 'Image optimization completed.'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        return True
    except ImportError:
        logger.warning("google_speech package is not installed. Skipping notification.")
        return False

# Main function
def main() -> None:
    """Main function."""
    args = parse_arguments()

    # Change to the specified working directory
    if not args.dir.is_dir():
        logger.error(f"Specified directory {args.dir} does not exist. Exiting.")
        sys.exit(1)

    os.chdir(args.dir)

    # Find JPG and JPEG images and process them
    image_files = glob.glob('*.jpg') + glob.glob('*.jpeg')
    image_files = [Path(f) for f in image_files]

    # Process images in parallel
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.threads) as executor:
        futures = [executor.submit(process_image, infile, args.overwrite, args.verbose)
                   for infile in image_files]
        concurrent.futures.wait(futures)

    # Notify completion if google_speech is installed
    notify_completion()

    # Print the parent path
    logger.info(f"\nProcessing complete: {args.dir.absolute()}")

if __name__ == "__main__":
    main()
