#!/usr/bin/env python3

import argparse
import concurrent.futures
import glob
import logging
import os
import platform
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
    parser.add_argument('-n', '--no-append-text', action='store_true',
                        help='Do not append "-IM" to the output image name.')
    return parser.parse_args()

# Logging configuration
logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

def run_command(command: List[str], verbose: bool) -> None:
    """Run a command and optionally print its output."""
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if verbose:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        print()  # Blank line to separate commands

# Image processing function
def process_image(infile: Path, overwrite_mode: bool, verbose_mode: bool, no_append_text: bool) -> None:
    """Process a single image file."""
    if infile.name.endswith('-IM.jpg') or infile.name.endswith('-IM.jpeg'):
        logger.info(f"Skipped: {infile}")
        return

    base_name = infile.stem
    with tempfile.TemporaryDirectory() as temp_dir:
        resized_image_path = Path(temp_dir) / infile.name

        # Resize the image if the dimensions are too large
        try:
            img_info = subprocess.check_output([
                'magick', 'identify', '-format', '%wx%h', str(infile)
            ]).decode('utf-8').strip()
            width, height = map(int, img_info.split('x'))
            if width > 5120 or height > 5120:
                run_command([
                    'magick', 'convert', str(infile),
                    '-resize', '5120x5120>',
                    str(resized_image_path)
                ], verbose_mode)
            else:
                resized_image_path = infile
        except subprocess.CalledProcessError as e:
            logger.error(f"Error processing {infile}: {e}")
            return

        outfile_suffix = '' if no_append_text else '-IM'
        outfile = infile.with_name(f"{base_name}{outfile_suffix}.jpg")

        # Compress the image
        try:
            run_command([
                'magick', 'convert', str(resized_image_path),
                '-strip', '-interlace', 'JPEG', '-quality', '85%',
                str(outfile)
            ], verbose_mode)
        except subprocess.CalledProcessError as e:
            logger.error(f"Error compressing {infile}: {e}")
            return

        logger.info(f"Processed: {outfile}")

        if overwrite_mode:
            infile.unlink()

def install_packages_if_needed() -> None:
    """Install required packages if running on a Debian-based system."""
    try:
        subprocess.run(['google_speech', '--version'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    except subprocess.CalledProcessError:
        if os.path.exists('/usr/bin/apt'):
            try:
                subprocess.run(['sudo', 'apt', 'update'], check=True)
                subprocess.run(['sudo', 'apt', 'install', '-y', 'sox', 'libsox-dev'], check=True)
            except subprocess.CalledProcessError as e:
                logger.error(f"Failed to install required packages: {e}")
                sys.exit(1)

# Function to check if google_speech is installed and send notification
def notify_completion() -> bool:
    """Check if google_speech is installed and send notification."""
    install_packages_if_needed()
    try:
        import google_speech
        subprocess.run(['google_speech', 'Image optimization completed.'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        
        win_path = subprocess.check_output(['wslpath', '-w', str(Path.cwd())]).decode('utf-8').strip()
        
        print()
        print(f"Windows Path: {win_path}")
        
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
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_THREADS) as executor:
        futures = [executor.submit(process_image, infile, args.overwrite, args.verbose, args.no_append_text)
                   for infile in image_files]
        concurrent.futures.wait(futures)

    # Notify completion if google_speech is installed
    notify_completion()

    # Print the parent path
    logger.info(f"\nProcessing complete: {args.dir.absolute()}")

if __name__ == "__main__":
    main()
