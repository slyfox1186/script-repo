#!/usr/bin/env python3

import os
import argparse
import subprocess
import re
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

def is_wsl():
    try:
        with open('/proc/version', 'r') as f:
            return 'microsoft' in f.read().lower()
    except FileNotFoundError:
        return False

def convert_to_wsl_path(path):
    try:
        result = subprocess.run(['wslpath', '-w', path], capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return path

def get_video_quality(file_path, verbose=False):
    if verbose:
        print(f"Processing video: {file_path}")
    try:
        result = subprocess.run(
            ['ffprobe', '-v', 'error', '-select_streams', 'v:0', 
             '-show_entries', 'stream=width,height,bit_rate,avg_frame_rate,codec_name', 
             '-of', 'default=noprint_wrappers=1', file_path],
            capture_output=True,
            text=True,
            check=True
        )
        output = result.stdout
        width = int(re.search(r'width=(\d+)', output).group(1))
        height = int(re.search(r'height=(\d+)', output).group(1))
        bit_rate = int(re.search(r'bit_rate=(\d+)', output).group(1))
        frame_rate = re.search(r'avg_frame_rate=(\d+/\d+)', output).group(1)
        codec_name = re.search(r'codec_name=(\w+)', output).group(1)

        # Calculate frame rate
        num, denom = map(int, frame_rate.split('/'))
        frame_rate = num / denom if denom != 0 else 0

        # A more sophisticated metric for quality
        # Factors: Resolution, Bit Rate, Frame Rate, Codec
        quality = (width * height * frame_rate * bit_rate) / 1_000_000  # Adjusted metric for quality

        # Adjust quality score based on codec (example adjustment)
        if codec_name in ["h265", "hevc"]:
            quality *= 1.5  # H.265/HEVC has better quality at lower bit rates

        return file_path, quality

    except (subprocess.CalledProcessError, AttributeError, ValueError) as e:
        if verbose:
            print(f"Error processing {file_path}: {e}")
        return file_path, 0

def find_mp4_files(root_dir, verbose=False):
    mp4_files = [str(path) for path in Path(root_dir).rglob("*.mp4")]
    if verbose:
        print(f"Found {len(mp4_files)} MP4 files.")
    return mp4_files

def create_bash_script(input_file, output_file):
    with open(output_file, 'w') as script:
        script.write(f"""#!/bin/bash
playlist='<?xml version="1.0" encoding="UTF-8"?>
<playlist version="1" xmlns="http://xspf.org/ns/0/">
    <trackList>\\n'
while IFS= read -r file; do
    playlist+=$'<track>\\n<location>file://'$file$'</location>\\n</track>\\n'
done < {input_file}
playlist+='</trackList>
</playlist>'
echo "$playlist" > {output_file}
""")
    os.chmod(output_file, 0o755)

def main():
    parser = argparse.ArgumentParser(description="Rank MP4 video files by quality.")
    parser.add_argument("root_dir", type=str, help="Root directory to search for MP4 files")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose output")
    parser.add_argument("-p", "--plain-output", action="store_true", help="Plain output format")
    parser.add_argument("-l", "--log-file", type=str, help="Log file to write output")
    parser.add_argument("-c", "--create-playlist", action="store_true", help="Create VLC playlist")
    parser.add_argument("--force-linux-path", action="store_true", help="Force Linux path on WSL")

    args = parser.parse_args()
    root_dir = args.root_dir
    verbose = args.verbose
    plain_output = args.plain_output
    log_file = args.log_file
    create_playlist_flag = args.create_playlist
    force_linux_path = args.force_linux_path

    mp4_files = find_mp4_files(root_dir, verbose)

    video_qualities = []
    with ThreadPoolExecutor(max_workers=os.cpu_count()) as executor:
        future_to_file = {executor.submit(get_video_quality, file, verbose): file for file in mp4_files}
        for future in as_completed(future_to_file):
            file, quality = future.result()
            video_qualities.append((file, quality))

    video_qualities.sort(key=lambda x: x[1], reverse=True)

    wsl = is_wsl() and not force_linux_path

    output_lines = []
    if not plain_output:
        output_lines.append(f"Folder Path: {os.path.abspath(root_dir)}\n")
        output_lines.append("Rank  Quality        File Path\n")
        output_lines.append("----  -------------  ---------\n")
    for i, (file, quality) in enumerate(video_qualities, start=1):
        if wsl:
            file = convert_to_wsl_path(file)
        if plain_output:
            output_lines.append(f"{file}\n")
        else:
            output_lines.append(f"{i:<4}  {quality:<13.1f}  {file}\n")

    output = ''.join(output_lines)
    print(output)

    if log_file:
        with open(log_file, 'w') as f:
            f.write(output)

    if create_playlist_flag:
        input_log_file = "results.txt"
        output_playlist_file = "vlc_playlist.xspf"
        with open(input_log_file, 'w') as results_file:
            results_file.write(''.join([line for line in output_lines if line.strip()]))  # Write only non-empty lines to results.txt
        create_bash_script(input_log_file, output_playlist_file)

if __name__ == "__main__":
    main()
