#!/usr/bin/env python3

import os
import argparse
import subprocess
import re
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import quote

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

        num, denom = map(int, frame_rate.split('/'))
        frame_rate = num / denom if denom != 0 else 0

        quality = (width * height * frame_rate * bit_rate) / 1_000_000

        if codec_name in ["h265", "hevc"]:
            quality *= 1.5
        elif codec_name in ["h264", "avc"]:
            quality *= 1.2
        elif codec_name in ["vp9"]:
            quality *= 1.3

        return file_path, quality
    except subprocess.CalledProcessError as e:
        if verbose:
            print(f"Error processing {file_path}: {e}")
        return file_path, 0

def find_mp4_files(root_dir, verbose=False):
    if verbose:
        print(f"Searching for MP4 files in directory: {root_dir}")
    mp4_files = []
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.lower().endswith('.mp4'):
                full_path = os.path.join(dirpath, filename)
                mp4_files.append(full_path)
    if verbose:
        print(f"Found {len(mp4_files)} MP4 files.")
    return mp4_files

def create_bash_script(input_log_file, output_playlist_file):
    bash_script_content = f"""#!/bin/bash
usage() {{
    echo "Usage: $0 -i <input_log_file> -o <output_playlist_file>"
    exit 1
}}
while getopts ":i:o:" opt; do
    case $opt in
        i) input_log_file="$OPTARG" ;;
        o) output_playlist_file="$OPTARG" ;;
        *) usage ;;
    esac
done
if [ -z "$input_log_file" ] || [ -z "$output_playlist_file" ]; then
    usage
fi
if [ ! -f "$input_log_file" ]; then
    echo "Input log file does not exist."
    exit 1
fi
echo "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>" > "$output_playlist_file"
echo "<playlist xmlns=\\"http://xspf.org/ns/0/\\" xmlns:vlc=\\"http://www.videolan.org/vlc/playlist/ns/0/\\" version=\\"1\\">" >> "$output_playlist_file"
echo "    <title>Playlist</title>" >> "$output_playlist_file"
echo "    <trackList>" >> "$output_playlist_file"
count=0
while IFS= read -r line; do
    escaped_line=$(echo "$line" | sed 's/&/\\&amp;/g; s/</\\&lt;/g; s/>/\\&gt;/g; s/'"'"'/\\&apos;/g; s/"/\\&quot;/g')
    escaped_line=$(echo "$escaped_line" | sed 's|\\\\|/|g')
    escaped_line=$(echo "$escaped_line" | sed 's|:/:||g')
    escaped_line=$(echo "$escaped_line" | sed 's|%|%25|g')
    escaped_line=$(echo "$escaped_line" | sed 's| |%20|g')
    escaped_line=$(echo "$escaped_line" | sed 's|#|%23|g')
    echo "        <track>" >> "$output_playlist_file"
    echo "            <location>file:///$escaped_line</location>" >> "$output_playlist_file"
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
rm "$0"
"""

    bash_script_path = "create_vlc_playlist.sh"
    with open(bash_script_path, "w") as bash_script_file:
        bash_script_file.write(bash_script_content)
    
    os.chmod(bash_script_path, 0o755)
    subprocess.run(["/bin/bash", bash_script_path, "-i", input_log_file, "-o", output_playlist_file])

def main():
    parser = argparse.ArgumentParser(description="Rank MP4 files by quality")
    parser.add_argument('root_dir', type=str, help="Root directory to search for MP4 files")
    parser.add_argument('-l', '--log', type=str, help="Log output to a specified file")
    parser.add_argument('-p', '--plain', action='store_true', help="Only output file paths without any other strings")
    parser.add_argument('-f', '--force-linux-path', action='store_true', help="Force output to use Linux paths even if running under WSL")
    parser.add_argument('-c', '--create-playlist', action='store_true', help="Create and run a Bash script to create a VLC playlist file from results.txt")
    parser.add_argument('-v', '--verbose', action='store_true', help="Enable verbose output")
    args = parser.parse_args()

    root_dir = args.root_dir
    log_file = args.log
    plain_output = args.plain
    force_linux_path = args.force_linux_path
    create_playlist_flag = args.create_playlist
    verbose = args.verbose

    mp4_files = find_mp4_files(root_dir, verbose)

    video_qualities = []
    with ThreadPoolExecutor() as executor:
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
        file_path = Path(file).as_posix()
        if plain_output:
            output_lines.append(f"{file_path}\n")
        else:
            output_lines.append(f"{i:<4}  {quality:<13.1f}  {file_path}\n")

    output = ''.join(output_lines)
    print(output)

    if log_file:
        with open(log_file, 'w', encoding='utf-8') as f:
            f.write(output)

    if create_playlist_flag:
        input_log_file = "results.txt"
        output_playlist_file = "vlc_playlist.xspf"
        with open(input_log_file, 'w', encoding='utf-8') as results_file:
            results_file.write(''.join([line for line in output_lines if line.strip()]))
        create_bash_script(input_log_file, output_playlist_file)

if __name__ == "__main__":
    main()
