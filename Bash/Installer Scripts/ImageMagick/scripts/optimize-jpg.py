#!/usr/bin/env python3

import os
import sys
import argparse
import subprocess
import tempfile
from multiprocessing import cpu_count, Pool
from functools import partial

# Constants
MAX_THREADS = 32  # User can set the maximum number of threads here

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
def parse_arguments():
    parser = argparse.ArgumentParser(description='Optimize JPG images.')
    parser.add_argument('-d', '--dir', default='.', help='Specify the working directory where images are located.')
    parser.add_argument('-o', '--overwrite', action='store_true', help='Enable overwrite mode. Original images will be overwritten.')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output.')
    parser.add_argument('-t', '--threads', type=int, default=MAX_THREADS, help='Specify the maximum number of threads to use (default is set by MAX_THREADS variable).')
    return parser.parse_args()

# Logging function
def log(message, verbose):
    if verbose:
        print(message)

# Image processing function
def process_image(infile, overwrite_mode, verbose_mode):
    base_name, extension = os.path.splitext(infile)
    with tempfile.TemporaryDirectory() as temp_dir:
        mpc_file = os.path.join(temp_dir, f"{os.path.basename(base_name)}.mpc")
        outfile = f"{base_name}-IM{extension}"

        convert_base_opts = [
            '-filter', 'Triangle', '-define', 'filter:support=2',
            '-thumbnail', subprocess.check_output(['identify', '-ping', '-format', '%wx%h', infile]).decode('utf-8').strip(),
            '-strip', '-unsharp', '0.25x0.08+8.3+0.045', '-dither', 'None', '-posterize', '136', '-quality', '82',
            '-define', 'jpeg:fancy-upsampling=off', '-auto-level', '-enhance', '-interlace', 'none',
            '-colorspace', 'sRGB'
        ]

        # First attempt to process with full options
        try:
            subprocess.run(['convert', infile] + convert_base_opts + ['-sampling-factor', '2x2', '-limit', 'area', '0', mpc_file], check=True)
        except subprocess.CalledProcessError:
            log(f"First attempt failed for {infile}, retrying without '-sampling-factor 2x2 -limit area 0'...", verbose_mode)
            try:
                subprocess.run(['convert', infile] + convert_base_opts + [mpc_file], check=True)
            except subprocess.CalledProcessError:
                log(f"Error: Second attempt failed for {infile} as well.", verbose_mode)
                return

        # Final convert from MPC to output image
        try:
            subprocess.run(['convert', mpc_file, outfile], check=True)
            print(f"Processed: {outfile}")
        except subprocess.CalledProcessError:
            print(f"Failed to process: {outfile}")

        # Cleanup
        if overwrite_mode:
            os.remove(infile)

# Main function
def main():
    args = parse_arguments()

    # Change to the specified working directory
    try:
        os.chdir(args.dir)
    except FileNotFoundError:
        print(f"Specified directory {args.dir} does not exist. Exiting.")
        sys.exit(1)

    # Check for running processes and terminate them
    for process in ['magick', 'convert', 'parallel']:
        try:
            subprocess.run(['pkill', '-x', process], check=True)
            log(f"Terminating running process: {process}", args.verbose)
        except subprocess.CalledProcessError:
            pass

    # Determine the number of parallel jobs
    num_jobs = min(MAX_THREADS, args.threads)
    log(f"Starting image processing with {num_jobs} parallel jobs...", args.verbose)

    # Find JPG images and process them
    jpg_files = [f for f in os.listdir(args.dir) if f.lower().endswith('.jpg') and not f.lower().endswith('-im.jpg')]

    with Pool(num_jobs) as pool:
        pool.map(partial(process_image, overwrite_mode=args.overwrite, verbose_mode=args.verbose), jpg_files)

if __name__ == "__main__":
    main()
