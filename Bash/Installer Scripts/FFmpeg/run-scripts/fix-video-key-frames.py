#!/usr/bin/env python3

import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from contextlib import ExitStack

# Color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    NC = '\033[0m'

# Calculate max parallel jobs based on logical CPU count
cpu_count = os.cpu_count() or 2
MAX_PARALLEL = max(cpu_count // 2, 2)  # Max parallel jobs is logical CPUs / 2 or 2, whichever is greater

# List to store temporary files
temp_files = []

def parse_args():
    script_name = os.path.basename(sys.argv[0])
    parser = argparse.ArgumentParser(
        description="Trim start and end of video files while aligning with keyframes.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument('--start', type=float, default=0, help='Duration in seconds to trim from the start of the video.')
    parser.add_argument('--end', type=float, default=0, help='Duration in seconds to trim from the end of the video.')

    parser.add_argument('-f', '--file-list', type=str, help='Path to the text file containing the list of video files or single video path.')
    parser.add_argument('-i', '--input', type=str, help='Path to a single video file.')
    parser.add_argument('-o', '--overwrite', action='store_true', help='Overwrite the input file instead of creating a new one.')

    parser.add_argument('-a', '--append', type=str, default='-trimmed', help='Text to append to the output file name.')
    parser.add_argument('-p', '--prepend', type=str, default='', help='Text to prepend to the output file name.')
    parser.add_argument('-t', '--threads', type=int, default=MAX_PARALLEL, help='Number of threads for parallel processing.')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output.')

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
           ./{script_name} -o -t=2 -f="fix-start-of-video.txt"
        """)
        sys.exit(0)

    return args

def log(message, color=Colors.NC):
    print(f"{color}{message}{Colors.NC}")

def get_video_info(file_path):
    command = [
        'ffprobe', '-v', 'error',
        '-select_streams', 'v:0',
        '-show_entries', 'stream=avg_frame_rate,duration',
        '-show_entries', 'format=duration',
        '-of', 'json',
        file_path
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise ValueError(f"Error getting video info: {result.stderr}")
    
    info = json.loads(result.stdout)
    duration = float(info['format']['duration'])
    fps = eval(info['streams'][0]['avg_frame_rate'])
    return duration, fps

def get_keyframe_time(file_path, time_offset, search_forward=True):
    direction = '+' if search_forward else '-'
    command = [
        'ffprobe', '-v', 'error',
        '-select_streams', 'v:0',
        '-skip_frame', 'nokey',
        '-show_entries', 'frame=pkt_pts_time',
        '-of', 'csv=p=0',
        '-read_intervals', f'{time_offset}%{direction}5',  # Search 5 seconds forward or backward
        file_path
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise ValueError(f"Error getting keyframe time: {result.stderr}")
    
    output = result.stdout.strip().split('\n')
    if not output or output[0] == '':
        return None
    return float(output[0])

def find_nearest_keyframe(file_path, target_time, duration, start=True):
    if start:
        forward_keyframe = get_keyframe_time(file_path, target_time, search_forward=True)
        if forward_keyframe is not None:
            return forward_keyframe
        return target_time
    else:
        backward_keyframe = get_keyframe_time(file_path, target_time, search_forward=False)
        if backward_keyframe is not None:
            return backward_keyframe
        return target_time

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
        duration, fps = get_video_info(file_path)
        
        start_time = max(find_nearest_keyframe(file_path, start, duration, start=True), start) if start > 0 else 0
        end_time = find_nearest_keyframe(file_path, duration - end, duration, start=False) if end > 0 else duration

        if verbose:
            log(f"Trimming {file_path} from {start_time:.2f}s to {end_time:.2f}s", Colors.YELLOW)

        base_name = Path(file_path).stem
        extension = Path(file_path).suffix
        final_output = f"{prepend_text}{base_name}{append_text}{extension}" if not overwrite else file_path
        temp_output_dir = Path(file_path).parent

        with ExitStack() as stack:
            temp_output = stack.enter_context(tempfile.NamedTemporaryFile(delete=False, suffix=extension, dir=temp_output_dir))
            temp_files.append(temp_output.name)

            command = [
                'ffmpeg',
                '-hide_banner',
                '-i', file_path,
                '-ss', f'{start_time:.3f}',
                '-to', f'{end_time:.3f}',
                '-c', 'copy',
                '-avoid_negative_ts', 'make_zero',
                '-map', '0',
                '-y',
                temp_output.name
            ]

            log(f"Running command: {' '.join(command)}", Colors.YELLOW)
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            
            for line in process.stderr:
                print(line, end='')

            process.wait()

            if process.returncode == 0:
                if overwrite:
                    shutil.move(temp_output.name, file_path)
                    log(f"Successfully processed and overwritten {file_path}", Colors.GREEN)
                else:
                    shutil.move(temp_output.name, final_output)
                    log(f"Successfully processed {file_path} into {final_output}", Colors.GREEN)
            else:
                raise subprocess.CalledProcessError(process.returncode, command)

    except Exception as e:
        log(f"Error processing {file_path}: {str(e)}", Colors.RED)

def main():
    args = parse_args()

    # Adjust prepend and append text based on the overwrite flag
    prepend_text = '' if args.overwrite else args.prepend
    append_text = '' if args.overwrite else args.append

    # Output the settings
    log("Settings:", Colors.YELLOW)
    log(f"  Input file: {args.input}", Colors.YELLOW)
    log(f"  File list: {args.file_list}", Colors.YELLOW)
    log(f"  Start trim: {args.start} seconds", Colors.YELLOW)
    log(f"  End trim: {args.end} seconds", Colors.YELLOW)
    log(f"  Append text: {append_text}", Colors.YELLOW)
    log(f"  Prepend text: {prepend_text}", Colors.YELLOW)
    log(f"  Overwrite: {args.overwrite}", Colors.YELLOW)
    log(f"  Verbose: {args.verbose}", Colors.YELLOW)
    log(f"  Threads: {args.threads}", Colors.YELLOW)
    
    video_files = []
    if args.file_list:
        with open(args.file_list, 'r') as f:
            video_files = [line.strip() for line in f]
    elif args.input:
        video_files.append(args.input)

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
