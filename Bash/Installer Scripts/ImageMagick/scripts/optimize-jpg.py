#!/usr/bin/env python3

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/ImageMagick/scripts/optimize-jpg.py

import argparse
import concurrent.futures
import logging
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import List, Tuple

try:
    from termcolor import colored
except ImportError:
    def colored(text, color=None, on_color=None, attrs=None):
        return text

# Constants
MAX_THREADS = os.cpu_count()
DEFAULT_THREADS = MAX_THREADS
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

# Thread-safe progress tracking
_progress_lock = threading.Lock()
_progress = {'processed': 0, 'skipped': 0, 'failed': 0, 'bytes_saved': 0, 'total': 0}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Optimize and convert images using ImageMagick.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  %(prog)s -d ./photos -q 90\n"
            "  %(prog)s -d ./photos -o -n --dry-run\n"
            "  %(prog)s -d ./photos -r -f png -t 4\n"
        )
    )
    parser.add_argument('-d', '--dir', type=Path, default=Path.cwd(),
                        help='Working directory where images are located (default: current dir).')
    parser.add_argument('-o', '--overwrite', action='store_true',
                        help='Overwrite original images after processing.')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Enable verbose output.')
    parser.add_argument('-n', '--no-append-text', action='store_true',
                        help='Do not append "-IM" to the output image name.')
    parser.add_argument('-r', '--recursive', action='store_true',
                        help='Recursively search for image files in subdirectories.')
    parser.add_argument('-f', '--format', choices=['jpg', 'png', 'tiff'], default='jpg',
                        help='Output image format (default: jpg).')
    parser.add_argument('-q', '--quality', type=int, default=82,
                        help='Image quality for compression, 1-100 (default: 82).')
    parser.add_argument('-b', '--backup', action='store_true',
                        help='Create backups of original images before processing.')
    parser.add_argument('-t', '--threads', type=int, default=DEFAULT_THREADS,
                        help=f'Number of parallel threads (default: {DEFAULT_THREADS}).')
    parser.add_argument('-m', '--preserve-metadata', action='store_true',
                        help='Preserve image metadata (EXIF, etc.) during processing.')
    parser.add_argument('-l', '--logfile', action='store_true',
                        help='Also log output to image_processing.log.')
    parser.add_argument('--dry-run', action='store_true',
                        help='Show what would be processed without making changes.')
    return parser.parse_args()


def setup_logging(log_to_file: bool, verbose: bool) -> None:
    handlers = [logging.StreamHandler()]
    if log_to_file:
        handlers.append(logging.FileHandler('image_processing.log'))

    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format='%(message)s', handlers=handlers)


def run_command(command: List[str], verbose: bool = False) -> subprocess.CompletedProcess:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    output_lines = result.stdout.splitlines() + result.stderr.splitlines()

    for line in output_lines:
        if re.search(r'fail|failure|fatal|error', line, re.IGNORECASE):
            logging.error(colored(line, 'red'))
        elif verbose:
            logging.debug(line)

    return result


def check_system_dependencies() -> None:
    required_commands = {'magick': 'ImageMagick', 'identify': 'ImageMagick'}
    missing = []

    for cmd, package_name in required_commands.items():
        if not shutil.which(cmd):
            missing.append(package_name)

    if missing:
        unique = list(set(missing))
        logging.error(colored(f"Missing required system dependencies: {', '.join(unique)}", 'red'))
        logging.info("Install using your system's package manager:")
        logging.info("  Debian/Ubuntu:  sudo apt install imagemagick")
        logging.info("  macOS:          brew install imagemagick")
        logging.info("  Conda:          conda install -c conda-forge imagemagick")
        sys.exit(1)


def get_image_dimensions(filepath: Path) -> Tuple[int, int]:
    output = subprocess.check_output(
        ['identify', '-ping', '-format', '%wx%h', str(filepath)]
    ).decode('utf-8').strip()
    width, height = map(int, output.split('x'))
    return width, height


def calculate_resize_dimensions(orig_width: int, orig_height: int) -> Tuple[int, int]:
    if orig_width <= MAX_WIDTH and orig_height <= MAX_HEIGHT:
        return orig_width, orig_height

    width_ratio = orig_width / MAX_WIDTH
    height_ratio = orig_height / MAX_HEIGHT

    if width_ratio > height_ratio:
        new_width = MAX_WIDTH
        new_height = int(orig_height * MAX_WIDTH / orig_width)
    else:
        new_height = MAX_HEIGHT
        new_width = int(orig_width * MAX_HEIGHT / orig_height)

    return new_width, new_height


def format_bytes(num_bytes: int) -> str:
    if num_bytes < 1024:
        return f"{num_bytes} B"
    elif num_bytes < 1024 * 1024:
        return f"{num_bytes / 1024:.1f} KB"
    elif num_bytes < 1024 * 1024 * 1024:
        return f"{num_bytes / (1024 * 1024):.1f} MB"
    else:
        return f"{num_bytes / (1024 * 1024 * 1024):.2f} GB"


def update_progress(status: str, bytes_saved: int = 0) -> None:
    with _progress_lock:
        _progress[status] += 1
        _progress['bytes_saved'] += bytes_saved
        done = _progress['processed'] + _progress['skipped'] + _progress['failed']
        total = _progress['total']
        pct = (done / total * 100) if total > 0 else 0
        bar_len = 30
        filled = int(bar_len * done / total) if total > 0 else 0
        bar = '=' * filled + '-' * (bar_len - filled)
        saved_str = format_bytes(_progress['bytes_saved'])
        sys.stdout.write(
            f"\r  [{bar}] {done}/{total} ({pct:.0f}%) | "
            f"OK: {_progress['processed']}  Skip: {_progress['skipped']}  "
            f"Fail: {_progress['failed']}  Saved: {saved_str}   "
        )
        sys.stdout.flush()


def process_image(
    infile: Path,
    overwrite_mode: bool,
    verbose_mode: bool,
    no_append_text: bool,
    output_format: str,
    quality: int,
    backup: bool,
    preserve_metadata: bool,
    recursive_mode: bool,
    base_dir: Path,
    dry_run: bool = False,
) -> None:
    if infile.name.endswith(f'-IM.{output_format}'):
        logging.debug(colored(f"  Skipped (already optimized): {infile.name}", 'blue'))
        update_progress('skipped')
        return

    if dry_run:
        outfile_suffix = '' if no_append_text else '-IM'
        outfile = infile.parent / f"{infile.stem}{outfile_suffix}.{output_format}"
        rel = outfile.relative_to(base_dir) if recursive_mode else outfile.name
        logging.info(colored(f"  [DRY RUN] Would process: {infile.name} -> {rel}", 'cyan'))
        update_progress('processed')
        return

    original_size = infile.stat().st_size
    base_name = infile.stem
    output_dir = infile.parent

    with tempfile.TemporaryDirectory() as temp_dir:
        resized_image_path = Path(temp_dir) / infile.name

        if backup:
            backup_path = infile.with_suffix(f'.bak{infile.suffix}')
            shutil.copy2(str(infile), str(backup_path))
            logging.debug(colored(f"  Backup: {backup_path.name}", 'yellow'))

        # Resize if dimensions exceed limits
        try:
            orig_width, orig_height = get_image_dimensions(infile)
            new_width, new_height = calculate_resize_dimensions(orig_width, orig_height)

            if new_width != orig_width or new_height != orig_height:
                logging.debug(
                    f"  Resizing {infile.name}: {orig_width}x{orig_height} -> {new_width}x{new_height}"
                )
                run_command(
                    ['magick', str(infile), '-resize', f'{new_width}x{new_height}', str(resized_image_path)],
                    verbose_mode,
                )
            else:
                resized_image_path = infile
        except subprocess.CalledProcessError as e:
            logging.error(colored(f"  Error reading dimensions for {infile.name}: {e}", 'red'))
            update_progress('failed')
            return

        outfile_suffix = '' if no_append_text else '-IM'
        outfile = output_dir / f"{base_name}{outfile_suffix}.{output_format}"

        try:
            if output_format.lower() in ('jpg', 'jpeg'):
                _process_jpg(resized_image_path, outfile, quality, preserve_metadata, verbose_mode)
            else:
                _process_other(resized_image_path, outfile, output_format, quality, preserve_metadata, verbose_mode)
        except subprocess.CalledProcessError as e:
            logging.error(colored(f"  Error processing {infile.name}: {e}", 'red'))
            update_progress('failed')
            return

        # Calculate size difference
        if outfile.exists():
            new_size = outfile.stat().st_size
            saved = original_size - new_size
            saved_str = format_bytes(abs(saved))
            if saved > 0:
                pct = (saved / original_size * 100) if original_size > 0 else 0
                size_info = colored(f"-{saved_str} ({pct:.1f}%)", 'green')
            elif saved < 0:
                size_info = colored(f"+{saved_str} (larger)", 'yellow')
            else:
                size_info = "same size"

            rel_path = outfile.relative_to(base_dir) if recursive_mode else outfile.name
            # Print on a new line so the progress bar doesn't clobber it
            sys.stdout.write('\r' + ' ' * 100 + '\r')
            logging.info(
                colored(f"  Processed: ", 'green')
                + f"{rel_path}  [{format_bytes(original_size)} -> {format_bytes(new_size)}] {size_info}"
            )
            update_progress('processed', bytes_saved=max(saved, 0))
        else:
            logging.error(colored(f"  Output file not created for {infile.name}", 'red'))
            update_progress('failed')
            return

        if overwrite_mode and outfile != infile:
            infile.unlink()
            logging.debug(colored(f"  Removed original: {infile.name}", 'yellow'))


def _process_jpg(
    infile: Path, outfile: Path, quality: int, preserve_metadata: bool, verbose: bool
) -> None:
    try:
        dimensions = f"{get_image_dimensions(infile)[0]}x{get_image_dimensions(infile)[1]}"
    except subprocess.CalledProcessError:
        dimensions = subprocess.check_output(
            ['identify', '-ping', '-format', '%wx%h', str(infile)]
        ).decode('utf-8').strip()

    opts = [
        '-filter', 'Triangle',
        '-define', 'filter:support=2',
        '-thumbnail', dimensions,
        '-unsharp', '0.25x0.08+8.3+0.045',
        '-dither', 'None',
        '-posterize', '136',
        '-quality', str(quality),
        '-define', 'jpeg:fancy-upsampling=off',
        '-auto-level',
        '-enhance',
        '-interlace', 'none',
        '-colorspace', 'sRGB',
    ]

    if not preserve_metadata:
        opts.insert(0, '-strip')

    # First attempt with sampling factor
    try:
        subprocess.run(
            ['magick', str(infile)] + opts + ['-sampling-factor', '2x2', '-limit', 'area', '0', str(outfile)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        return
    except subprocess.CalledProcessError:
        if verbose:
            logging.debug(f"  Retrying {infile.name} without sampling-factor...")

    # Fallback without sampling factor
    subprocess.run(
        ['magick', str(infile)] + opts + [str(outfile)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )


def _process_other(
    infile: Path, outfile: Path, output_format: str, quality: int, preserve_metadata: bool, verbose: bool
) -> None:
    interlace = 'none' if output_format.lower() in ('png', 'tiff', 'tif') else 'JPEG'

    cmd = ['magick', str(infile)]
    if not preserve_metadata:
        cmd.append('-strip')
    cmd += ['-interlace', interlace, '-quality', f'{quality}', str(outfile)]

    run_command(cmd, verbose)


def collect_image_files(directory: Path, recursive: bool) -> List[Path]:
    extensions = ['*.jpg', '*.jpeg', '*.png', '*.tiff', '*.tif']
    files = []
    for ext in extensions:
        if recursive:
            files.extend(list(directory.rglob(ext)))
        else:
            files.extend(list(directory.glob(ext)))
    # Sort for deterministic processing order
    files.sort()
    return files


def print_header(args: argparse.Namespace, file_count: int) -> None:
    logging.info("")
    logging.info(colored("=" * 60, 'cyan'))
    logging.info(colored("  Image Optimizer", 'cyan'))
    logging.info(colored("=" * 60, 'cyan'))
    logging.info(f"  Directory:   {args.dir.absolute()}")
    logging.info(f"  Format:      {args.format.upper()}")
    logging.info(f"  Quality:     {args.quality}")
    logging.info(f"  Threads:     {min(args.threads, MAX_THREADS)}")
    logging.info(f"  Recursive:   {'yes' if args.recursive else 'no'}")
    logging.info(f"  Overwrite:   {'yes' if args.overwrite else 'no'}")
    logging.info(f"  Metadata:    {'preserve' if args.preserve_metadata else 'strip'}")
    logging.info(f"  Append -IM:  {'no' if args.no_append_text else 'yes'}")
    if args.dry_run:
        logging.info(colored("  Mode:        DRY RUN (no changes will be made)", 'yellow'))
    logging.info(f"  Images:      {file_count}")
    logging.info(colored("-" * 60, 'cyan'))
    logging.info("")


def print_summary(elapsed: float) -> None:
    logging.info("")
    logging.info(colored("=" * 60, 'cyan'))
    logging.info(colored("  Summary", 'cyan'))
    logging.info(colored("=" * 60, 'cyan'))
    logging.info(f"  Processed:   {_progress['processed']}")
    logging.info(f"  Skipped:     {_progress['skipped']}")
    logging.info(f"  Failed:      {_progress['failed']}")
    logging.info(f"  Saved:       {format_bytes(_progress['bytes_saved'])}")
    logging.info(f"  Elapsed:     {elapsed:.1f}s")
    logging.info(colored("=" * 60, 'cyan'))
    logging.info("")


def main() -> None:
    args = parse_arguments()
    setup_logging(args.logfile, args.verbose)
    check_system_dependencies()

    if not args.dir.is_dir():
        logging.error(colored(f"Directory does not exist: {args.dir}", 'red'))
        sys.exit(1)

    image_files = collect_image_files(args.dir, args.recursive)

    if not image_files:
        logging.info(colored("No image files found.", 'yellow'))
        sys.exit(0)

    _progress['total'] = len(image_files)
    print_header(args, len(image_files))

    start_time = time.time()

    with concurrent.futures.ThreadPoolExecutor(max_workers=min(args.threads, MAX_THREADS)) as executor:
        futures = {
            executor.submit(
                process_image,
                infile, args.overwrite, args.verbose, args.no_append_text,
                args.format, args.quality, args.backup, args.preserve_metadata,
                args.recursive, args.dir, args.dry_run,
            ): infile
            for infile in image_files
        }
        for future in concurrent.futures.as_completed(futures):
            infile = futures[future]
            try:
                future.result()
            except Exception as e:
                logging.error(colored(f"  Unhandled error processing {infile.name}: {e}", 'red'))
                update_progress('failed')

    # Clear the progress bar line
    sys.stdout.write('\r' + ' ' * 100 + '\r')
    sys.stdout.flush()

    elapsed = time.time() - start_time
    print_summary(elapsed)

    logging.info(colored(f"Output: {args.dir.absolute()}", 'green'))


if __name__ == "__main__":
    main()
