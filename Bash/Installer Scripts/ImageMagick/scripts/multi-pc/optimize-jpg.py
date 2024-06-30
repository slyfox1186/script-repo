#!/usr/bin/env python3

import argparse
import concurrent.futures
import logging
import os
import subprocess
import sys
from pathlib import Path
from termcolor import colored

# Constants
MAX_THREADS = os.cpu_count()
MAX_WIDTH, MAX_HEIGHT = 8000, 6000

# Argument parser
def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Optimize and convert images.')
    parser.add_argument('-d', '--dir', type=Path, default=Path.cwd(),
                        help='Specify the working directory where images are located.')
    parser.add_argument('-o', '--overwrite', action='store_true',
                        help='Enable overwrite mode. Original images will be overwritten.')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Enable verbose output.')
    parser.add_argument('-r', '--recursive', action='store_true',
                        help='Recursively search for all image files.')
    parser.add_argument('-f', '--format', choices=['jpg', 'png', 'tiff'], default='jpg',
                        help='Specify output image format.')
    parser.add_argument('-q', '--quality', type=int, default=85,
                        help='Specify image quality for compression (1-100).')
    parser.add_argument('-t', '--threads', type=int, default=MAX_THREADS,
                        help='Specify number of threads to use for parallel processing.')
    parser.add_argument('-m', '--preserve-metadata', action='store_true',
                        help='Preserve metadata during image processing.')
    return parser.parse_args()

# Logging configuration
def setup_logging() -> None:
    logging.basicConfig(level=logging.INFO, format='%(message)s', handlers=[logging.StreamHandler()])

# Image processing function
def process_image(infile: Path, overwrite_mode: bool, verbose_mode: bool, output_format: str, quality: int, preserve_metadata: bool, recursive_mode: bool, base_dir: Path) -> None:
    if infile.name.endswith(f'-IM.{output_format}'):
        logging.info(colored(f"Skipped: {infile}", 'blue'))
        return

    base_name = infile.stem
    output_dir = infile.parent

    try:
        img_info = subprocess.check_output(['identify', '-ping', '-format', '%wx%h', str(infile)])
        orig_width, orig_height = map(int, img_info.decode('utf-8').strip().split('x'))
        if orig_width > MAX_WIDTH or orig_height > MAX_HEIGHT:
            if orig_width > orig_height:
                new_width = MAX_WIDTH
                new_height = int(orig_height * MAX_WIDTH / orig_width)
            else:
                new_height = MAX_HEIGHT
                new_width = int(orig_width * MAX_HEIGHT / orig_height)
            temp_outfile = infile.with_name(f"{base_name}-resized{infile.suffix}")
            subprocess.run(['magick', str(infile), '-resize', f'{new_width}x{new_height}', str(temp_outfile)], check=True)
        else:
            temp_outfile = infile

        final_outfile = output_dir / f"{base_name}-IM.{output_format}"

        convert_base_opts = [
            'magick',
            str(temp_outfile),
            '-filter', 'Triangle',
            '-define', 'filter:support=2',
            '-thumbnail', f'{MAX_WIDTH}x{MAX_HEIGHT}>',
            '-unsharp', '0.25x0.25+8+0.065',
            '-dither', 'None',
            '-posterize', '136',
            '-quality', str(quality),
            '-define', 'jpeg:fancy-upsampling=off',
            '-auto-level',
            '-enhance',
            '-interlace', 'none',
            '-colorspace', 'sRGB'
        ]

        if not preserve_metadata:
            convert_base_opts.insert(2, '-strip')

        subprocess.run(convert_base_opts + ['-sampling-factor', '2x2', '-limit', 'area', '0', str(final_outfile)], check=True)

        if temp_outfile != infile:
            temp_outfile.unlink()

        if overwrite_mode:
            infile.unlink()
            final_outfile.rename(infile.with_name(f"{base_name}-IM{infile.suffix}"))

        if recursive_mode:
            logging.info(colored(f"Processed: {final_outfile.relative_to(base_dir)}", 'green'))
        else:
            logging.info(colored(f"Processed: {final_outfile.name}", 'green'))

    except subprocess.CalledProcessError as e:
        logging.error(colored(f"Error processing {infile}: {e}", 'red'))
        with open('error_report.log', 'a') as f:
            f.write(f"Error processing {infile}: {e}\n")

# Main function
def main() -> None:
    args = parse_arguments()
    setup_logging()

    if not args.dir.is_dir():
        logging.error(colored(f"Specified directory {args.dir} does not exist. Exiting.", 'red'))
        sys.exit(1)

    os.chdir(args.dir)

    if args.recursive:
        image_files = list(args.dir.rglob('*.jpg')) + list(args.dir.rglob('*.jpeg'))
    else:
        image_files = list(args.dir.glob('*.jpg')) + list(args.dir.glob('*.jpeg'))

    logging.info(f"Found {len(image_files)} image files")

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.threads) as executor:
        futures = [executor.submit(process_image, 
                                   infile, 
                                   args.overwrite, 
                                   args.verbose, 
                                   args.format, 
                                   args.quality, 
                                   args.preserve_metadata, 
                                   args.recursive, 
                                   args.dir) for infile in image_files]
        concurrent.futures.wait(futures)

    logging.info(colored(f"\nProcessing complete: {args.dir.absolute()}", 'green'))

if __name__ == "__main__":
    main()
