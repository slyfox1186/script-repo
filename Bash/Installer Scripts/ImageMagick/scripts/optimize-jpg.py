#!/usr/bin/env python3

import argparse
import concurrent.futures
import glob
import logging
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from termcolor import colored
from typing import List

# Constants
MAX_THREADS = os.cpu_count()
DEFAULT_THREADS = MAX_THREADS
MASTER_FOLDER = Path.home() / "python-venv"
VENV_NAME = "myenv"
VENV_PATH = MASTER_FOLDER / VENV_NAME
GOOGLE_SPEECH_PACKAGE = "google_speech"
TERMCOLOR_PACKAGE = "termcolor"
REQUIRED_PACKAGES = ['sox', 'libsox-dev', 'python3-venv']
MAX_WIDTH, MAX_HEIGHT = 8000, 6000

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
    parser = argparse.ArgumentParser(description='Optimize and convert images.')
    parser.add_argument('-d', '--dir', type=Path, default=Path.cwd(),
                        help='Specify the working directory where images are located.')
    parser.add_argument('-o', '--overwrite', action='store_true',
                        help='Enable overwrite mode. Original images will be overwritten.')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Enable verbose output.')
    parser.add_argument('-n', '--no-append-text', action='store_true',
                        help='Do not append "-IM" to the output image name.')
    parser.add_argument('-r', '--recursive', action='store_true',
                        help='Recursively search for all image files.')
    parser.add_argument('-f', '--format', choices=['jpg', 'png', 'tiff'], default='jpg',
                        help='Specify output image format.')
    parser.add_argument('-q', '--quality', type=int, default=85,
                        help='Specify image quality for compression (1-100).')
    parser.add_argument('-b', '--backup', action='store_true',
                        help='Create backups of original images before processing.')
    parser.add_argument('-t', '--threads', type=int, default=DEFAULT_THREADS,
                        help='Specify number of threads to use for parallel processing.')
    parser.add_argument('-m', '--preserve-metadata', action='store_true',
                        help='Preserve metadata during image processing.')
    parser.add_argument('-l', '--logfile', action='store_true',
                        help='Enable logging to a file.')
    return parser.parse_args()

# Logging configuration
def setup_logging(log_to_file: bool) -> None:
    """Setup logging configuration."""
    handlers = [logging.StreamHandler()]
    if log_to_file:
        handlers.append(logging.FileHandler('image_processing.log'))
    
    logging.basicConfig(level=logging.INFO, format='%(message)s', handlers=handlers)

def run_command(command: List[str], verbose: bool = False) -> None:
    """Run a command and optionally print its output."""
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    output_lines = result.stdout.splitlines() + result.stderr.splitlines()

    for line in output_lines:
        if re.search(r'fail|failure|fatal|error', line, re.IGNORECASE):
            logging.error(colored(line, 'red'))
            with open('error_report.log', 'a') as f:
                f.write(line + '\n')
        elif 'Successfully installed google_speech-1.2.0' in line:
            logging.info(colored(line, 'green'))
        else:
            logging.info(line)
    if verbose:
        logging.info()  # Blank line to separate commands

def check_and_install_apt_packages() -> None:
    """Check and install required APT packages if necessary."""
    missing_packages = []

    for pkg in REQUIRED_PACKAGES:
        result = subprocess.run(['dpkg-query', '-W', '-f=${Status}', pkg], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if 'ok installed' not in result.stdout:
            missing_packages.append(pkg)

    if missing_packages:
        logging.info(colored(f"Installing missing packages: {', '.join(missing_packages)}", 'yellow'))
        try:
            subprocess.run(['sudo', 'apt', 'update'], check=True)
            subprocess.run(['sudo', 'apt', 'install', '-y'] + missing_packages, check=True)
        except subprocess.CalledProcessError as e:
            logging.error(colored(f"Failed to install required packages: {e}", 'red'))
            sys.exit(1)

def create_virtualenv() -> None:
    """Create a Python virtual environment and install google_speech."""
    logging.info(colored(f"Creating Python virtual environment at {VENV_PATH}...", 'yellow'))
    os.makedirs(VENV_PATH, exist_ok=True)
    subprocess.run(['python3', '-m', 'venv', VENV_PATH], check=True)
    install_package(GOOGLE_SPEECH_PACKAGE)
    install_package(TERMCOLOR_PACKAGE)

def install_package(package: str) -> None:
    """Install a package in the virtual environment."""
    activate_script = str(VENV_PATH / 'bin' / 'activate')
    logging.info(colored(f"Installing {package} in virtual environment...", 'yellow'))
    result = subprocess.run(f"source {activate_script} && pip install --upgrade pip && pip install {package}", shell=True, executable="/bin/bash", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    output_lines = result.stdout.splitlines() + result.stderr.splitlines()
    for line in output_lines:
        if 'Successfully installed' in line:
            logging.info(colored(line, 'green'))
        elif re.search(r'fail|failure|fatal|error', line, re.IGNORECASE):
            logging.error(colored(line, 'red'))
            with open('error_report.log', 'a') as f:
                f.write(line + '\n')
        else:
            logging.info(line)
    if result.returncode != 0:
        logging.error(colored(f"Failed to install {package}: {result.stderr}", 'red'))
        sys.exit(1)

def check_package_installed(package: str) -> bool:
    """Check if a package is installed in the virtual environment."""
    result = subprocess.run([VENV_PATH / 'bin' / 'pip', 'show', package], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode == 0

# Image processing function
def process_image(infile: Path, overwrite_mode: bool, verbose_mode: bool, no_append_text: bool, output_format: str, quality: int, backup: bool, preserve_metadata: bool, recursive_mode: bool, base_dir: Path) -> None:
    """Process a single image file."""
    if infile.name.endswith(f'-IM.{output_format}'):
        logging.info(colored(f"Skipped: {infile}", 'blue'))
        return

    base_name = infile.stem
    output_dir = infile.parent
    with tempfile.TemporaryDirectory() as temp_dir:
        resized_image_path = Path(temp_dir) / infile.name

        if backup:
            backup_path = infile.with_suffix(f".bak{infile.suffix}")
            infile.rename(backup_path)
            infile = backup_path

        # Resize the image if the dimensions are too large
        try:
            img_info = subprocess.check_output(['identify', '-ping', '-format', '%wx%h', str(infile)])
            orig_width, orig_height = map(int, img_info.decode('utf-8').strip().split('x'))
            if orig_width > MAX_WIDTH or orig_height > MAX_HEIGHT:
                if orig_width > orig_height:
                    if orig_width / MAX_WIDTH > orig_height / MAX_HEIGHT:
                        new_width = MAX_WIDTH
                        new_height = int(orig_height * MAX_WIDTH / orig_width)
                    else:
                        new_height = MAX_HEIGHT
                        new_width = int(orig_width * MAX_HEIGHT / orig_height)
                else:
                    if orig_height / MAX_WIDTH > orig_width / MAX_HEIGHT:
                        new_height = MAX_WIDTH
                        new_width = int(orig_width * MAX_WIDTH / orig_height)
                    else:
                        new_width = MAX_HEIGHT
                        new_height = int(orig_height * MAX_HEIGHT / orig_width)
                run_command(['magick', 'convert', str(infile), '-resize', f'{new_width}x{new_height}', str(resized_image_path)], verbose_mode)
            else:
                resized_image_path = infile
        except subprocess.CalledProcessError as e:
            logging.error(colored(f"Error processing {infile}: {e}", 'red'))
            with open('error_report.log', 'a') as f:
                f.write(f"Error processing {infile}: {e}\n")
            return

        outfile_suffix = '' if no_append_text else '-IM'
        outfile = output_dir / f"{base_name}{outfile_suffix}.{output_format}"

        # Custom magick settings for JPG optimization
        if output_format.lower() == 'jpg' or output_format.lower() == 'jpeg':
            convert_base_opts = [
                '-filter', 'Triangle', '-define', 'filter:support=2',
                '-thumbnail', subprocess.check_output(['identify', '-ping',
                '-format', '%wx%h', str(resized_image_path)]).decode('utf-8').strip(),
                '-strip', '-unsharp', '0.25x0.08+8.3+0.045', '-dither', 'None',
                '-posterize', '136', '-quality', '82', '-define', 'jpeg:fancy-upsampling=off',
                '-auto-level', '-enhance', '-interlace', 'none', '-colorspace', 'sRGB'
            ]

            try:
                subprocess.run(['magick', str(resized_image_path)] + convert_base_opts +
                               ['-sampling-factor', '2x2', '-limit', 'area', '0', str(outfile)],
                               check=True)
            except subprocess.CalledProcessError:
                if verbose_mode:
                    logging.warning(f"First attempt failed for {infile}, retrying without '-sampling-factor 2x2 -limit area 0'...")
                try:
                    subprocess.run(['magick', str(resized_image_path)] + convert_base_opts + [str(outfile)], check=True)
                except subprocess.CalledProcessError:
                    logging.error(colored(f"Error: Second attempt failed for {infile} as well."))
                    return
        else:
            # Compress the image
            compress_command = [
                'magick', 'convert', str(resized_image_path),
                '-strip', '-interlace', 'JPEG', '-quality', f'{quality}%',
                str(outfile)
            ]
            if preserve_metadata:
                compress_command.remove('-strip')

            try:
                run_command(compress_command, verbose_mode)
            except subprocess.CalledProcessError as e:
                logging.error(colored(f"Error compressing {infile}: {e}", 'red'))
                with open('error_report.log', 'a') as f:
                    f.write(f"Error compressing {infile}: {e}\n")
                return

        if recursive_mode:
            logging.info(colored(f"Processed: {outfile.relative_to(base_dir)}", 'green'))
        else:
            logging.info(colored(f"Processed: {outfile.name}", 'green'))

        if overwrite_mode:
            infile.unlink()

def notify_completion() -> None:
    """Check if google_speech is installed and send notification."""
    check_and_install_apt_packages()

    if not check_package_installed(GOOGLE_SPEECH_PACKAGE):
        create_virtualenv()

    try:
        subprocess.run([VENV_PATH / 'bin' / 'google_speech', 'Image optimization completed.'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        win_path = subprocess.check_output(['wslpath', '-w', str(Path.cwd())]).decode('utf-8').strip()
        logging.info(colored(f"\nWindows Path: {win_path}", 'green'))
    except subprocess.CalledProcessError as e:
        logging.warning(colored("Failed to run google_speech command.", 'red'))

# Main function
def main() -> None:
    """Main function."""
    args = parse_arguments()

    # Setup logging based on the presence of the logfile argument
    setup_logging(args.logfile)

    # Change to the specified working directory
    if not args.dir.is_dir():
        logging.error(colored(f"Specified directory {args.dir} does not exist. Exiting.", 'red'))
        sys.exit(1)

    os.chdir(args.dir)

    # Find image files and process them
    if args.recursive:
        image_files = list(Path(args.dir).rglob('*.jpg')) + list(Path(args.dir).rglob('*.jpeg'))
    else:
        image_files = list(Path(args.dir).glob('*.jpg')) + list(Path(args.dir).glob('*.jpeg'))

    # Process images in parallel
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(args.threads, MAX_THREADS)) as executor:
        futures = {executor.submit(process_image, infile, args.overwrite, args.verbose, args.no_append_text, args.format, args.quality, args.backup, args.preserve_metadata, args.recursive, args.dir): infile for infile in image_files}
        for future in concurrent.futures.as_completed(futures):
            infile = futures[future]
            try:
                future.result()
            except Exception as e:
                logging.error(colored(f"Error processing {infile}: {e}", 'red'))

    # Notify completion if google_speech is installed
    notify_completion()

    # Print the parent path
    logging.info(colored(f"\nProcessing complete: {args.dir.absolute()}", 'green'))

if __name__ == "__main__":
    main()
