#!/usr/bin/env python3

import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# Color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    NC = '\033[0m'

MAX_PARALLEL = 2  # Default maximum number of parallel jobs
temp_files = []   # List to store temporary files

def parse_args():
    script_name = os.path.basename(sys.argv[0])
    parser = argparse.ArgumentParser(
        description="Trim start and end of video files.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument('-f', '--file', type=str, help='Path to the text file containing the list of video files.')
    parser.add_argument('-i', '--input', type=str, help='Path to a single video file.')
    parser.add_argument('-l', '--list', type=str, help='Path to a text file containing the full paths to the video files.')
    parser.add_argument('--start', type=int, default=0, help='Duration in seconds to trim from the start of the video.')
    parser.add_argument('--end', type=int, default=0, help='Duration in seconds to trim from the end of the video.')
    parser.add_argument('-a', '--append', type=str, default='-trimmed', help='Text to append to the output file name.')
    parser.add_argument('-p', '--prepend', type=str, default='', help='Text to prepend to the output file name.')
    parser.add_argument('-o', '--overwrite', action='store_true', help='Overwrite the input file instead of creating a new one.')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output.')
    parser.add_argument('-t', '--threads', type=int, default=MAX_PARALLEL, help='Number of threads for parallel processing.')
    parser.add_argument('-e', '--examples', action='store_true', help='Show command line examples.')
    args = parser.parse_args()

    if args.examples:
        print(f"""
        Command Line Examples:

        1. Trim a single video file:
           ./{script_name} -i video.mp4 --start 10 --end 5

        2. Trim video files listed in a text file:
           ./{script_name} -f video_list.txt --start 10 --end 5

        3. Trim video files listed in a text file with verbose output:
           ./{script_name} -f video_list.txt --start 10 --end 5 -v

        4. Trim a single video file and overwrite the original:
           ./{script_name} -i video.mp4 --start 10 --end 5 -o

        5. Trim a single video file and specify number of threads:
           ./{script_name} -i video.mp4 --start 10 --end 5 -t 4

        6. Trim a single video file and change the output file name:
           ./{script_name} -i video.mp4 --start 10 --end 5 -p new- -a -new

        7. Batch process, overwrite, and utilize two threads using an input text file:
           ./{script_name} -o -t=2 -l="fix-start-of-video.txt"
        """)
        sys.exit(0)

    return args

def log(message, color=Colors.NC):
    print(f"{color}{message}{Colors.NC}")

def get_video_duration(file_path):
    result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                             '-of', 'default=noprint_wrappers=1:nokey=1', file_path],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return float(result.stdout.strip())

def get_keyframe_time(file_path, time_offset):
    result = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v', '-of', 'csv=p=0',
                             '-show_entries', 'frame=best_effort_timestamp_time',
                             '-read_intervals', f'{time_offset}%+{time_offset}', '-i', file_path],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout.decode('utf-8').strip().split('\n')[0]

def cleanup_temp_files():
    global temp_files
    for temp_file in temp_files:
        try:
            os.remove(temp_file)
            log(f"Deleted temporary file {temp_file}", Colors.GREEN)
        except Exception as e:
            log(f"Error deleting temporary file {temp_file}: {e}", Colors.RED)
    temp_files = []

def handle_exit(signum, frame):
    log("Termination signal received. Cleaning up...", Colors.YELLOW)
    cleanup_temp_files()
    sys.exit(0)

signal.signal(signal.SIGINT, handle_exit)
signal.signal(signal.SIGTERM, handle_exit)

def process_video(file_path, start, end, prepend_text, append_text, overwrite, verbose):
    try:
        duration = get_video_duration(file_path)
    except ValueError:
        log(f"Error: Unable to get duration for {file_path}", Colors.RED)
        return

    start_time = get_keyframe_time(file_path, start) if start > 0 else '0'
    end_time = get_keyframe_time(file_path, duration - end) if end > 0 else str(duration)

    if verbose:
        log(f"Trimming from {start_time} to {end_time}.", Colors.YELLOW)

    base_name = Path(file_path).stem
    extension = Path(file_path).suffix
    final_output = f"{prepend_text}{base_name}{append_text}{extension}" if not overwrite else file_path
    temp_output_dir = Path(file_path).parent

    with tempfile.NamedTemporaryFile(delete=False, suffix=extension, dir=temp_output_dir) as temp_output:
        temp_files.append(temp_output.name)
        command = ['ffmpeg', '-y', '-hide_banner', '-ss', start_time, '-i', file_path,
                   '-to', end_time, '-c', 'copy', temp_output.name]

        if subprocess.run(command).returncode == 0:
            if overwrite:
                shutil.move(temp_output.name, file_path)
                temp_files.remove(temp_output.name)
                log(f"Successfully processed and overwritten {file_path}", Colors.GREEN)
            else:
                shutil.move(temp_output.name, final_output)
                temp_files.remove(temp_output.name)
                log(f"Successfully processed {file_path} into {final_output}", Colors.GREEN)
        else:
            log(f"Failed to process {file_path}", Colors.RED)
            os.remove(temp_output.name)
            temp_files.remove(temp_output.name)

def main():
    args = parse_args()

    # Adjust prepend and append text based on the overwrite flag
    prepend_text = '' if args.overwrite else args.prepend
    append_text = '' if args.overwrite else args.append

    # Output the settings
    log("Settings:", Colors.YELLOW)
    log(f"  Input file: {args.input}", Colors.YELLOW)
    log(f"  File list: {args.file}", Colors.YELLOW)
    log(f"  Start trim: {args.start} seconds", Colors.YELLOW)
    log(f"  End trim: {args.end} seconds", Colors.YELLOW)
    log(f"  Append text: {append_text}", Colors.YELLOW)
    log(f"  Prepend text: {prepend_text}", Colors.YELLOW)
    log(f"  Overwrite: {args.overwrite}", Colors.YELLOW)
    log(f"  Verbose: {args.verbose}", Colors.YELLOW)
    log(f"  Threads: {args.threads}", Colors.YELLOW)
    
    video_files = []
    if args.file:
        with open(args.file, 'r') as f:
            video_files = [line.strip() for line in f]
    elif args.input:
        video_files.append(args.input)
    elif args.list:
        with open(args.list, 'r') as f:
            video_files = [line.strip() for line in f]

    if not video_files:
        log("Error: No input video or file list provided, or file does not exist.", Colors.RED)
        sys.exit(1)

    max_parallel = args.threads if args.threads else MAX_PARALLEL

    with ThreadPoolExecutor(max_workers=max_parallel) as executor:
        futures = {executor.submit(process_video, file_path, args.start, args.end, prepend_text, append_text, args.overwrite, args.verbose): file_path for file_path in video_files}

        for future in as_completed(futures):
            file_path = futures[future]
            try:
                future.result()
            except Exception as e:
                log(f"Error processing {file_path}: {e}", Colors.RED)

    log("Processing completed.", Colors.GREEN)

if __name__ == "__main__":
    main()
