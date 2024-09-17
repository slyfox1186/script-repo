#!/usr/bin/env python3

import argparse
import concurrent.futures
import logging
import os
import re
import subprocess
import sys
import tempfile
import shutil
from pathlib import Path
from typing import List, Tuple

import termcolor
from termcolor import colored

# Constants
MAX_THREADS = os.cpu_count() or 1
DEFAULT_THREADS = MAX_THREADS
MASTER_FOLDER = Path.home() / "python-venv"
VENV_NAME = "myenv"
VENV_PATH = MASTER_FOLDER / VENV_NAME
MAX_WIDTH, MAX_HEIGHT = 8000, 6000

REQUIRED_APT_PACKAGES = ['sox', 'libsox-dev', 'python3-venv']
REQUIRED_PIP_PACKAGES = ['google_speech', 'termcolor']

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

EXTENSIONS = {
    'jpg': ['.jpg', '.jpeg'],
    'png': ['.png'],
    'tiff': ['.tif', '.tiff']
}

def parse_arguments() -> argparse.Namespace:
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
    parser.add_argument('-q', '--quality', type=int, default=82,  # Changed from 85 to 82
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

class ColoredFormatter(logging.Formatter):
    def format(self, record):
        message = super().format(record)
        if record.levelno == logging.ERROR:
            return colored(message, 'red')
        elif record.levelno == logging.WARNING:
            return colored(message, 'yellow')
        else:
            return colored(message, 'white')

def setup_logging(log_to_file: bool) -> None:
    handlers = [logging.StreamHandler(sys.stdout)]
    if log_to_file:
        handlers.append(logging.FileHandler('image_processing.log'))

    for handler in handlers:
        handler.setFormatter(ColoredFormatter('%(message)s'))

    logging.basicConfig(level=logging.INFO, handlers=handlers)

def run_command(command: List[str], verbose: bool = False) -> None:
    result = subprocess.run(command, capture_output=True, text=True)
    output_lines = result.stdout.splitlines() + result.stderr.splitlines()

    for line in output_lines:
        if re.search(r'fail|failure|fatal|error', line, re.IGNORECASE):
            logging.error(colored(line, 'red'))
            with open('error_report.log', 'a') as f:
                f.write(line + '\n')
        elif 'Successfully installed' in line:
            logging.info(colored(line, 'green'))
        else:
            logging.info(colored(line, 'white'))
    if verbose:
        logging.info('')  # Blank line to separate commands

def check_and_install_apt_packages() -> None:
    missing_apt_packages = []
    for pkg in REQUIRED_APT_PACKAGES:
        result = subprocess.run(['dpkg-query', '-W', '-f=${Status}', pkg], capture_output=True, text=True)
        if 'install ok installed' not in result.stdout:
            missing_apt_packages.append(pkg)

    if missing_apt_packages:
        logging.info(colored(f"Installing missing APT packages: {', '.join(missing_apt_packages)}", 'yellow'))
        try:
            subprocess.run(['sudo', 'apt', 'update'], check=True)
            subprocess.run(['sudo', 'apt', 'install', '-y'] + missing_apt_packages, check=True)
        except subprocess.CalledProcessError as e:
            logging.error(colored(f"Failed to install required APT packages: {e}", 'red'))
            sys.exit(1)

def check_and_install_pip_packages() -> None:
    missing_pip_packages = [pkg for pkg in REQUIRED_PIP_PACKAGES if not check_package_installed(pkg)]
    
    if missing_pip_packages:
        logging.info(colored(f"Installing missing PIP packages: {', '.join(missing_pip_packages)}", 'yellow'))
        for package in missing_pip_packages:
            install_package(package)

def create_virtualenv() -> None:
    if not VENV_PATH.exists():
        os.makedirs(VENV_PATH, exist_ok=True)
        subprocess.run(['python3', '-m', 'venv', VENV_PATH], check=True)
        subprocess.run([VENV_PATH / 'bin' / 'pip', 'install', '--upgrade', 'pip'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def install_package(package: str) -> None:
    logging.info(colored(f"Installing {package} in virtual environment...", 'yellow'))
    result = subprocess.run([VENV_PATH / 'bin' / 'pip', 'install', package], capture_output=True, text=True)
    for line in result.stdout.splitlines() + result.stderr.splitlines():
        if 'Successfully installed' in line:
            logging.info(colored(line, 'green'))
        elif re.search(r'fail|failure|fatal|error', line, re.IGNORECASE):
            logging.error(colored(line, 'red'))
            with open('error_report.log', 'a') as f:
                f.write(line + '\n')
        else:
            logging.info(colored(line, 'white'))
    if result.returncode != 0:
        logging.error(colored(f"Failed to install {package}: {result.stderr}", 'red'))
        sys.exit(1)

def check_package_installed(package: str) -> bool:
    return subprocess.run([VENV_PATH / 'bin' / 'pip', 'show', package], capture_output=True).returncode == 0

def colorize_filename(filename_stem: str, suffix: str) -> str:
    # Use regex to split the filename
    parts = re.split(r'(-)', filename_stem)
    
    filename = ''
    for part in parts:
        if part == '-':
            filename += colored('-', 'yellow')
        elif part == 'IM':
            filename += colored('IM', 'magenta')
        else:
            filename += colored(part, 'cyan')

    # Combine all parts with correct coloring
    colored_filename = f"{filename}{colored('.', 'white')}{colored(suffix[1:], 'red')}"
    return colored_filename

def process_image(infile: Path, args: argparse.Namespace, base_dir: Path) -> None:
    if infile.stem.endswith('-IM'):
        skipped_text = f"{colored('Skipped', 'blue')}{colored(':', 'yellow')}"
        colored_filename = colorize_filename(infile.stem, infile.suffix)
        logging.info(f"{skipped_text} {colored_filename}")
        return

    base_name = infile.stem
    output_dir = infile.parent
    with tempfile.TemporaryDirectory() as temp_dir:
        resized_image_path = Path(temp_dir) / infile.name

        if args.backup:
            backup_path = infile.with_suffix(f".bak{infile.suffix}")
            if not backup_path.exists():
                shutil.copy2(infile, backup_path)

        try:
            img_info = subprocess.check_output(['identify', '-ping', '-format', '%wx%h', str(infile)])
            orig_width, orig_height = map(int, img_info.decode('utf-8').strip().split('x'))
            if orig_width > MAX_WIDTH or orig_height > MAX_HEIGHT:
                new_width, new_height = calculate_new_dimensions(orig_width, orig_height)
                run_command(['magick', str(infile), '-resize', f'{new_width}x{new_height}', str(resized_image_path)], args.verbose)
            else:
                resized_image_path = infile
        except subprocess.CalledProcessError as e:
            logging.error(colored(f"Error processing {infile}: {e}", 'red'))
            with open('error_report.log', 'a') as f:
                f.write(f"Error processing {infile}: {e}\n")
            return

        outfile_suffix = '' if args.no_append_text else '-IM'
        outfile = output_dir / f"{base_name}{outfile_suffix}.{args.format}"

        if args.format.lower() in ['jpg', 'jpeg']:
            process_jpg(resized_image_path, outfile, args)
        else:
            process_other_format(resized_image_path, outfile, args)

        log_processed_file(outfile, args.recursive, base_dir)

        if args.overwrite:
            infile.unlink()

def calculate_new_dimensions(orig_width: int, orig_height: int) -> Tuple[int, int]:
    aspect_ratio = orig_width / orig_height
    if orig_width > MAX_WIDTH or orig_height > MAX_HEIGHT:
        if aspect_ratio > 1:
            new_width = min(orig_width, MAX_WIDTH)
            new_height = int(new_width / aspect_ratio)
        else:
            new_height = min(orig_height, MAX_HEIGHT)
            new_width = int(new_height * aspect_ratio)
        return new_width, new_height
    else:
        return orig_width, orig_height

def process_jpg(resized_image_path: Path, outfile: Path, args: argparse.Namespace) -> None:
    convert_base_opts = [
        '-filter', 'Triangle', '-define', 'filter:support=2',
        '-thumbnail', 'x'.join(map(str, calculate_new_dimensions(*map(int, subprocess.check_output(['identify', '-ping', '-format', '%wx%h', str(resized_image_path)]).decode('utf-8').strip().split('x'))))),
        '-strip', '-unsharp', '0.25x0.08+8.3+0.045', '-dither', 'None',
        '-posterize', '136', '-quality', str(args.quality),  # Use args.quality here
        '-define', 'jpeg:fancy-upsampling=off',
        '-auto-level', '-enhance', '-interlace', 'none', '-colorspace', 'sRGB'
    ]

    try:
        subprocess.run(['magick', str(resized_image_path)] + convert_base_opts + ['-sampling-factor', '4:2:0', '-limit', 'area', '0', str(outfile)], check=True)
    except subprocess.CalledProcessError:
        if args.verbose:
            logging.warning(colored(f"First attempt failed for {resized_image_path}, retrying without '-sampling-factor 4:2:0 -limit area 0'...", 'yellow'))
        try:
            subprocess.run(['magick', str(resized_image_path)] + convert_base_opts + [str(outfile)], check=True)
        except subprocess.CalledProcessError:
            logging.error(colored(f"Error: Second attempt failed for {resized_image_path} as well.", 'red'))

def process_other_format(resized_image_path: Path, outfile: Path, args: argparse.Namespace) -> None:
    compress_command = [
        'magick', str(resized_image_path),
        '-strip', '-interlace', 'JPEG', '-quality', f'{args.quality}%',
        str(outfile)
    ]
    if args.preserve_metadata:
        compress_command.remove('-strip')

    try:
        run_command(compress_command, args.verbose)
    except subprocess.CalledProcessError as e:
        logging.error(colored(f"Error compressing {resized_image_path}: {e}", 'red'))
        with open('error_report.log', 'a') as f:
            f.write(f"Error compressing {resized_image_path}: {e}\n")

def log_processed_file(outfile: Path, recursive: bool, base_dir: Path) -> None:
    status_text = f"{colored('Processed', 'green')}{colored(':', 'yellow')}"
    colored_filename = colorize_filename(outfile.stem, outfile.suffix)
    logging.info(f"{status_text} {colored_filename}")

def notify_completion() -> None:
    try:
        subprocess.run([VENV_PATH / 'bin' / 'google_speech', 'Image optimization completed.'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        logging.info(colored("Image optimization completed.", 'green'))
    except subprocess.CalledProcessError:
        logging.warning(colored("Failed to run google_speech command.", 'yellow'))

def rainbow_text(text, start_color='red'):
    colors = ['red', 'yellow', 'green', 'cyan', 'blue', 'magenta']
    start_index = colors.index(start_color)
    colored_chars = []
    for i, char in enumerate(text):
        color = colors[(start_index + i) % len(colors)]
        colored_chars.append(colored(char, color))
    return ''.join(colored_chars)

def colorize_path(path: str) -> str:
    parts = re.split(r'([/\\])', path)
    colored_parts = []
    for part in parts:
        if part in ['/', '\\']:
            colored_parts.append(colored(part, 'yellow'))
        else:
            colored_parts.append(colored(part, 'cyan'))
    return ''.join(colored_parts)

def compression_quality_color(quality: int) -> str:
    if quality >= 85:
        return 'green'
    elif quality >= 75:
        return 'yellow'
    elif quality >= 50:
        return 'white'
    else:
        return 'red'

def main() -> None:
    args = parse_arguments()
    setup_logging(args.logfile)
    
    create_virtualenv()
    check_and_install_apt_packages()
    check_and_install_pip_packages()

    if not args.dir.is_dir():
        logging.error(colored(f"Specified directory {args.dir} does not exist. Exiting.", 'red'))
        sys.exit(1)

    os.chdir(args.dir)

    win_path = None
    if shutil.which('wslpath'):
        try:
            win_path = subprocess.check_output(['wslpath', '-w', str(Path.cwd())],
                                               stderr=subprocess.DEVNULL).decode('utf-8').strip()
        except subprocess.CalledProcessError:
            pass

    cpu_count = os.cpu_count()

    logging.info(f"{colored('Working Dir:', 'cyan')}{colored(':', 'yellow')} {colorize_path(str(Path.cwd()))}")
    if win_path:
        logging.info(f"{colored('Windows Path', 'cyan')}{colored(':', 'yellow')} {colorize_path(win_path)}")
    logging.info(f"\n{colored('Workers', 'cyan')}{colored(':', 'yellow')} {colored(str(cpu_count), 'cyan')}")
    logging.info(f"\n{colored('Output format', 'cyan')}{colored(':', 'yellow')} {colored(args.format.upper(), 'white')}")
    quality_color = compression_quality_color(args.quality)
    logging.info(f"{colored('Compression', 'cyan')} {rainbow_text('quality')}{colored(':', 'yellow')} {colored(str(args.quality), quality_color)}")
    if args.overwrite:
        logging.info(f"\n{colored('Overwrite mode', 'cyan')}{colored(':', 'yellow')} {colored('Enabled', 'green')}")
    if args.preserve_metadata:
        logging.info(f"{colored('Preserve metadata', 'cyan')}{colored(':', 'yellow')} {colored('Enabled', 'green')}")

    logging.info(f"\n{colored('='*31, 'blue')}\n")

    # Collect image files with appropriate extensions
    extensions = EXTENSIONS[args.format.lower()]
    image_files = []
    for ext in extensions:
        if args.recursive:
            image_files.extend(list(Path(args.dir).rglob(f'*{ext}')))
        else:
            image_files.extend(list(Path(args.dir).glob(f'*{ext}')))
    image_files.sort(key=lambda x: x.name)

    file_count = len(image_files)
    processing_text = f"{colored('Processing', 'cyan')} {colored(str(file_count), 'yellow')} {colored('File' + ('s' if file_count != 1 else ''), 'cyan')}{colored('...', 'yellow')}"
    logging.info(f"{processing_text}\n")

    with concurrent.futures.ThreadPoolExecutor(max_workers=min(args.threads, MAX_THREADS)) as executor:
        futures = {executor.submit(process_image, infile, args, args.dir): infile for infile in image_files}
        for future in concurrent.futures.as_completed(futures):
            infile = futures[future]
            try:
                future.result()
            except Exception as e:
                logging.error(colored(f"Error processing {infile.name}: {e}", 'red'))

    print()
    notify_completion()

if __name__ == "__main__":
    main()
