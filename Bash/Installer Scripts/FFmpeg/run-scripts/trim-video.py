#!/usr/bin/env python3

import argparse
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile

# Color codes — disabled when output is not a terminal
if sys.stdout.isatty():
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    NC = "\033[0m"
else:
    RED = GREEN = YELLOW = NC = ""

# Track temp files for cleanup on interrupt
_temp_files = set()


def _cleanup_and_exit(signum, frame):
    for path in _temp_files:
        try:
            os.remove(path)
        except OSError:
            pass
    sys.exit(1)


signal.signal(signal.SIGINT, _cleanup_and_exit)
signal.signal(signal.SIGTERM, _cleanup_and_exit)


def print_color(color, msg, end="\n"):
    print(f"{color}{msg}{NC}", end=end)


def find_nearest_keyframe(input_file, target_time):
    result = subprocess.run(
        [
            "ffprobe", "-hide_banner", "-v", "error", "-skip_frame", "nokey",
            "-select_streams", "v:0", "-show_entries", "frame=pkt_pts_time",
            "-of", "csv=p=0", input_file,
        ],
        capture_output=True, text=True,
    )
    nearest = None
    min_diff = None
    for line in result.stdout.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            pts = float(line)
        except ValueError:
            continue
        diff = abs(pts - target_time)
        if min_diff is None or diff < min_diff:
            min_diff = diff
            nearest = pts
    return nearest


def seconds_to_hms(seconds):
    seconds = int(round(seconds))
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    time_stamp = f"{h:02d}:{m:02d}:{s:02d}"
    return time_stamp


def parse_time(value):
    """Parse a time value that can be seconds or HH:MM:SS."""
    value = str(value)
    if re.match(r"^[0-9]+:[0-9]+:[0-9]+$", value):
        parts = value.split(":")
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    return float(value)


def get_duration(input_file):
    result = subprocess.run(
        [
            "ffprobe", "-hide_banner", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", "-i", input_file,
        ],
        capture_output=True, text=True,
    )
    output = result.stdout.strip()
    if not output:
        return None
    try:
        return float(output)
    except ValueError:
        return None


def get_first_keyframe_time(input_file):
    result = subprocess.run(
        [
            "ffprobe", "-hide_banner", "-v", "error", "-of", "default=noprint_wrappers=1:nokey=1",
            "-select_streams", "v:0", "-skip_frame", "nokey", "-show_frames",
            "-show_entries", "frame=pkt_dts_time", input_file,
        ],
        capture_output=True, text=True,
    )
    for line in result.stdout.strip().splitlines():
        line = line.strip()
        if re.match(r"^[0-9]+\.[0-9]+$", line):
            return float(line)
    return None


def get_end_keyframe_time(input_file, trim_end):
    result = subprocess.run(
        [
            "ffprobe", "-hide_banner", "-v", "error", "-select_streams", "v",
            "-of", "csv=p=0", "-show_entries", "frame=best_effort_timestamp_time",
            "-read_intervals", f"-{trim_end}%-{trim_end}", "-i", input_file,
        ],
        capture_output=True, text=True,
    )
    times = []
    for line in result.stdout.strip().splitlines():
        line = line.strip()
        if line:
            try:
                times.append(float(line))
            except ValueError:
                pass
    if times:
        return max(times)
    return None


def prompt_for_input():
    while True:
        path = input("Enter the path to the input video file (or 'q' to quit): ")
        if path == "q":
            print("Quitting...")
            sys.exit(0)
        if os.path.isfile(path):
            os.system("clear")
            return path
        print_color(RED, f"Error: The file {path} does not exist. Please try again.")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Trim video files using ffmpeg with keyframe-accurate cuts.",
        add_help=False,
    )
    parser.add_argument("-f", "--file", dest="file_list", default="")
    parser.add_argument("-i", "--input", dest="single_input_file", default="")
    parser.add_argument("-l", "--list", dest="input_list", default="")
    parser.add_argument("--start", dest="trim_start", default="0")
    parser.add_argument("--end", dest="trim_end", default="0")
    parser.add_argument("-a", "--append", dest="append_text", default="_trimmed")
    parser.add_argument("-p", "--prepend", dest="prepend_text", default="")
    parser.add_argument("-o", "--overwrite", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()

    if args.help:
        print_color(GREEN,
            f"Usage: {sys.argv[0]} [-f <file_list> | -i <input_file> | -l <input_list>] "
            "[--start <trim_start_seconds>] [--end <trim_end_seconds>] "
            "[--append <append_text>] [--prepend <prepend_text>] [--overwrite] [--verbose]"
        )
        print()
        print("Options:")
        print("  -h, --help             Display this help message.")
        print("  -f, --file             Specify the path to the text file containing the list of video files.")
        print("  -i, --input            Specify the path to a single video file directly.")
        print("  -l, --list             Specify the path to a text file containing the full paths to the video files.")
        print("      --start            Duration in seconds to trim from the start of the video.")
        print("      --end              Duration in seconds to trim from the end of the video.")
        print("  -a, --append           Specify text to append to the output file name. Ignored if --overwrite is used.")
        print("  -p, --prepend          Specify text to prepend to the output file name. Ignored if --overwrite is used.")
        print("  -o, --overwrite        Overwrite the input file instead of creating a new one.")
        print("  -v, --verbose          Enable verbose output.")
        print()
        print("Examples:")
        print(f"  {os.path.basename(sys.argv[0])} -v -i \"video.mp4\"")
        print(f"  {os.path.basename(sys.argv[0])} -o -v -i \"video.mp4\"")
        print(f"  {os.path.basename(sys.argv[0])} -l \"video_list.txt\"")
        sys.exit(1)

    # Verify ffmpeg and ffprobe are available
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            print_color(RED, f"Error: '{tool}' not found in PATH. Please install ffmpeg.")
            sys.exit(1)

    trim_start = parse_time(args.trim_start)
    trim_end = parse_time(args.trim_end)
    append_text = args.append_text
    prepend_text = args.prepend_text
    overwrite = args.overwrite
    verbose = args.verbose
    single_input_file = args.single_input_file
    file_list = args.file_list
    input_list = args.input_list
    batch_mode = bool(file_list or input_list)

    if overwrite:
        append_text = ""
        prepend_text = ""

    # Remove log file
    if os.path.isfile("video-processing.log"):
        os.remove("video-processing.log")

    interactive = not single_input_file and not file_list and not input_list

    while True:
        video_files = []

        if interactive:
            video_files.append(prompt_for_input())
        elif single_input_file:
            video_files.append(single_input_file)
        elif file_list and os.path.isfile(file_list):
            with open(file_list) as f:
                video_files = [line.strip() for line in f if line.strip()]
        elif input_list and os.path.isfile(input_list):
            with open(input_list) as f:
                video_files = [line.strip() for line in f if line.strip()]
        else:
            print_color(RED, "Error: No input video or file list provided, or file does not exist.")
            sys.exit(1)

        total_files = len(video_files)
        for file_idx, input_file in enumerate(video_files, 1):
            if not os.path.isfile(input_file):
                print_color(RED, f"Error: The file {input_file} does not exist.")
                continue

            prefix = f"[{file_idx}/{total_files}] " if total_files > 1 else ""
            print_color(GREEN, f"{prefix}Processing: {input_file}")

            total_duration = get_duration(input_file)
            if total_duration is None:
                print_color(RED, f"Error: Could not read duration of {input_file}. Skipping.")
                continue

            # Calculate start keyframe
            if trim_start > 0:
                formatted_start_time = find_nearest_keyframe(input_file, trim_start)
                if formatted_start_time is None:
                    print_color(YELLOW, f"No keyframe found near start time {trim_start}, using the exact time instead.")
                    formatted_start_time = trim_start
            else:
                formatted_start_time = get_first_keyframe_time(input_file)

            # Calculate end keyframe
            if trim_end > 0:
                formatted_end_time = get_end_keyframe_time(input_file, trim_end)
                if formatted_end_time is None:
                    print_color(YELLOW, f"No keyframe found near end time {trim_end}, using the exact time instead.")
                    formatted_end_time = total_duration - trim_end
            else:
                formatted_end_time = total_duration

            if verbose:
                start_hms = seconds_to_hms(formatted_start_time or 0)
                end_hms = seconds_to_hms(formatted_end_time or 0)
                print_color(YELLOW, f"Trimming from {start_hms} ({formatted_start_time}s) to {end_hms} ({formatted_end_time}s)")

            base_name, extension = os.path.splitext(input_file)
            if overwrite:
                final_output = input_file
            else:
                dir_name = os.path.dirname(input_file)
                base_only = os.path.basename(base_name)
                final_output = os.path.join(dir_name, f"{prepend_text}{base_only}{append_text}{extension}")

            # Build ffmpeg command
            cmd = ["ffmpeg", "-hide_banner"]
            if overwrite:
                cmd.append("-y")
            if formatted_start_time is not None:
                cmd.extend(["-ss", str(formatted_start_time)])
            cmd.extend(["-i", input_file, "-ss", "0"])
            if formatted_end_time is not None:
                cmd.extend(["-to", str(formatted_end_time)])
            cmd.extend(["-c", "copy"])

            if overwrite:
                temp_dir = os.path.dirname(input_file) or "."
                fd, temp_output = tempfile.mkstemp(suffix=extension, prefix="ffmpeg.", dir=temp_dir)
                os.close(fd)
                _temp_files.add(temp_output)
                cmd.append(temp_output)
                result = subprocess.run(cmd)
                if result.returncode == 0:
                    os.replace(temp_output, input_file)
                    _temp_files.discard(temp_output)
                    print_color(GREEN, f"Successfully processed and overwritten {input_file}\n")
                else:
                    if os.path.exists(temp_output):
                        os.remove(temp_output)
                    _temp_files.discard(temp_output)
                    print_color(RED, f"Failed to process {input_file}\n")
                    continue
            else:
                cmd.append(final_output)
                result = subprocess.run(cmd)
                if result.returncode == 0:
                    print_color(GREEN, f"Successfully processed {input_file} into {final_output}\n")
                else:
                    print_color(RED, f"Failed to process {input_file}\n")
                    continue

            # In interactive mode, prompt user to continue
            if interactive:
                choice = input("Press Enter to continue or 'q' to quit...")
                if choice.lower() == "q":
                    print_color(YELLOW, "Exiting as per user request.")
                    sys.exit(0)
                os.system("clear")

        # Only loop if truly interactive (no args given); otherwise exit
        if not interactive:
            break

    print_color(GREEN, "Processing completed.")


if __name__ == "__main__":
    main()
