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

def get_video_quality(file_path):
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
        elif codec_name in ["h264", "avc"]:
            quality *= 1.2  # H.264/AVC is very efficient
        elif codec_name in ["vp9"]:
            quality *= 1.3  # VP9 is also very efficient

        return file_path, quality
    except subprocess.CalledProcessError as e:
        print(f"Error processing {file_path}: {e}")
        return file_path, 0

def find_mp4_files(root_dir):
    mp4_files = []
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.lower().endswith('.mp4'):
                full_path = os.path.join(dirpath, filename)
                mp4_files.append(full_path)
    return mp4_files

def create_bash_script(input_log_file, output_playlist_file):
    bash_script_content = f"""#!/bin/bash
# Usage function
usage() {{
    echo "Usage: $0 -i <input_log_file> -o <output_playlist_file>"
    exit 1
}}
# Parse arguments
while getopts ":i:o:" opt; do
    case $opt in
        i) input_log_file="$OPTARG"
        ;;
        o) output_playlist_file="$OPTARG"
        ;;
        *) usage
        ;;
    esac
done
# Check if input and output files are provided
if [ -z "$input_log_file" ] || [ -z "$output_playlist_file" ]; then
    usage
fi
# Check if input file exists
if [ ! -f "$input_log_file" ]; then
    echo "Input log file does not exist."
    exit 1
fi
# Create VLC playlist file
echo "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>" > "$output_playlist_file"
echo "<playlist xmlns=\\"http://xspf.org/ns/0/\\" xmlns:vlc=\\"http://www.videolan.org/vlc/playlist/ns/0/\\" version=\\"1\\">" >> "$output_playlist_file"
echo "    <title>Playlist</title>" >> "$output_playlist_file"
echo "    <trackList>" >> "$output_playlist_file"
count=0
while IFS= read -r line; do
    # Escape special characters and format the path for VLC
    escaped_line=$(echo "$line" | sed 's/ /%20/g' | sed 's/(/%28/g' | sed 's/)/%29/g' | sed 's/!/%21/g' | sed "s/'/%27/g" | sed 's/,/%2C/g' | sed 's/\\\\/\\//g' | sed 's/&/\\&amp;/g')
    echo "        <track>" >> "$output_playlist_file"
    echo "            <location>file:///$escaped_line</location>" >> "$output_playlist_file"
    echo "            <duration></duration>" >> "$output_playlist_file"  # Duration is left empty as it needs to be calculated separately if needed
    echo "            <extension application=\\"http://www.videolan.org/vlc/playlist/0\\">" >> "$output_playlist_file"
    echo "                <vlc:id>$count</vlc:id>" >> "$output_playlist_file"
    echo "            </extension>" >> "$output_playlist_file"
    echo "        </track>" >> "$output_playlist_file"
    count=$((count + 1))
done < "$input_log_file"
echo "    </trackList>" >> "$output_playlist_file"
echo "    <extension application=\\"http://www.videolan.org/vlc/playlist/0\\">" >> "$output_playlist_file"
for i in $(seq 0 $((count - 1))); do
    echo "        <vlc:item tid=\\"$i\\"/>" >> "$output_playlist_file"
done
echo "    </extension>" >> "$output_playlist_file"
echo "</playlist>" >> "$output_playlist_file"
echo "VLC playlist created at $output_playlist_file"
"""

    bash_script_path = "create_vlc_playlist.sh"
    with open(bash_script_path, "w") as bash_script_file:
        bash_script_file.write(bash_script_content)
    
    # Make the script executable
    os.chmod(bash_script_path, 0o755)

    # Run the Bash script
    subprocess.run(["/bin/bash", bash_script_path, "-i", input_log_file, "-o", output_playlist_file])

def main():
    parser = argparse.ArgumentParser(description="Rank MP4 files by quality")
    parser.add_argument('root_dir', type=str, help="Root directory to search for MP4 files")
    parser.add_argument('-l', '--log', type=str, help="Log output to a specified file")
    parser.add_argument('-p', '--plain', action='store_true', help="Only output file paths without any other strings")
    parser.add_argument('-f', '--force-linux-path', action='store_true', help="Force output to use Linux paths even if running under WSL")
    parser.add_argument('-c', '--create-playlist', action='store_true', help="Create and run a Bash script to create a VLC playlist file from results.txt")
    args = parser.parse_args()

    root_dir = args.root_dir
    log_file = args.log
    plain_output = args.plain
    force_linux_path = args.force_linux_path
    create_playlist_flag = args.create_playlist

    mp4_files = find_mp4_files(root_dir)

    video_qualities = []
    with ThreadPoolExecutor() as executor:
        future_to_file = {executor.submit(get_video_quality, file): file for file in mp4_files}
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
        log_output_lines = []
        for i, (file, quality) in enumerate(video_qualities, start=1):
            if wsl:
                file = convert_to_wsl_path(file)
            if plain_output:
                log_output_lines.append(f"{file}\n")
            else:
                log_output_lines.append(f"{i:<4}  {quality:<13.1f}  {file}\n")
        
        log_output = ''.join(log_output_lines)
        with open(log_file, 'w') as f:
            f.write(log_output)

    if create_playlist_flag:
        input_log_file = "results.txt"
        output_playlist_file = "vlc_playlist.xspf"
        with open(input_log_file, 'w') as results_file:
            results_file.write(''.join([line for line in output_lines if line.strip()]))  # Write only non-empty lines to results.txt
        create_bash_script(input_log_file, output_playlist_file)

if __name__ == "__main__":
    main()
