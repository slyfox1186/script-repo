#!/usr/bin/env python3

import argparse
import concurrent.futures
import os
import pandas as pd
import subprocess

def show_help():
    help_text = """
    Usage: find_best_videos.py [OPTION]... DIRECTORY
    Recursively searches the specified DIRECTORY for MP4 files and ranks them by video quality.

    Options:
      -d, --display-values  Include quality values in the output log.
    """
    print(help_text)

def get_video_quality(video_file):
    cmd = [
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_name,width,height,r_frame_rate,bit_rate',
        '-of', 'csv=p=0', video_file
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        return None, None

    codec, width, height, frame_rate, bit_rate = result.stdout.strip().split(',')
    frame_rate = eval(frame_rate) if '/' in frame_rate else float(frame_rate)

    codec_weights = {
        'h264': 1.0,
        'hevc': 1.5,
        'vp9': 1.3,
        'av1': 1.4
    }
    codec_weight = codec_weights.get(codec, 1.0)

    width = int(width) if width else 0
    height = int(height) if height else 0
    bit_rate = int(bit_rate) if bit_rate else 0
    frame_rate = float(frame_rate) if frame_rate else 1.0

    quality = width * height * bit_rate * frame_rate * codec_weight
    return video_file, int(quality)

def find_mp4_files(search_dir):
    mp4_files = []
    for root, _, files in os.walk(search_dir):
        for file in files:
            if file.lower().endswith('.mp4'):
                mp4_files.append(os.path.join(root, file))
    return mp4_files

def format_percentage(value):
    return "{:.2f}%".format(value)

def calculate_quality_changes(log_content):
    lines = log_content.strip().split('\n')[2:]
    data = []
    for line in lines:
        parts = line.split()
        rank = int(parts[2])
        path = ' '.join(parts[4:])
        data.append((rank, path))
    
    df = pd.DataFrame(data, columns=['Weighted Rank', 'Path'])
    df['Change in Quality %'] = df['Weighted Rank'].pct_change() * 100
    df['Cumulative % Difference'] = df['Change in Quality %'].cumsum()
    
    df.loc[0, 'Change in Quality %'] = 0
    df.loc[0, 'Cumulative % Difference'] = 0
    
    df['Change in Quality %'] = df['Change in Quality %'].apply(format_percentage)
    df['Cumulative % Difference'] = df['Cumulative % Difference'].apply(format_percentage)
    
    return df

def log_sorted_videos_with_quality_changes(log_file_path):
    with open(log_file_path, 'r') as file:
        log_content = file.read()
    
    df = calculate_quality_changes(log_content)
    
    max_path_length = df['Path'].str.len().max()
    path_column_width = max(36, max_path_length)
    
    with open(log_file_path, 'w') as file:
        file.write("Video files sorted by quality (best to worst):\n\n")
        file.write("+--------------------------+-------------------------+------------------------+{}+\n".format('-' * (path_column_width + 2)))
        file.write("| Cumulative % Difference  | Change in Quality %     | Weighted Rank          | Path{} |\n".format(' ' * (path_column_width - 4)))
        file.write("+--------------------------+-------------------------+------------------------+{}+\n".format('-' * (path_column_width + 2)))
        for _, row in df.iterrows():
            file.write(f"| {row['Cumulative % Difference']:<24} | {row['Change in Quality %']:<23} | {row['Weighted Rank']:<22} | {row['Path']:<{path_column_width}} |\n")
            file.write("+--------------------------+-------------------------+------------------------+{}+\n".format('-' * (path_column_width + 2)))

def main():
    parser = argparse.ArgumentParser(description="Rank MP4 videos by quality.")
    parser.add_argument('directory', metavar='DIRECTORY', type=str, help='Directory to search for MP4 files.')
    parser.add_argument('-d', '--display-values', action='store_true', help='Include quality values in the output log.')
    args = parser.parse_args()

    search_dir = args.directory
    mp4_files = find_mp4_files(search_dir)
    
    with concurrent.futures.ThreadPoolExecutor() as executor:
        future_to_file = {executor.submit(get_video_quality, file): file for file in mp4_files}
        results = []
        for future in concurrent.futures.as_completed(future_to_file):
            file, quality = future.result()
            if quality is not None:
                results.append((file, quality))
    
    results.sort(key=lambda x: x[1], reverse=True)
    
    with open('video_quality_log.txt', 'w') as log_file:
        log_file.write("Video files sorted by quality (best to worst):\n\n")
        for video, quality in results:
            if args.display_values:
                log_file.write(f"Weighted Rank: {quality} Path: {video}\n")
            else:
                log_file.write(f"Path: {video}\n")
    
    log_sorted_videos_with_quality_changes('video_quality_log.txt')
    print("Log file generated: video_quality_log.txt")

if __name__ == '__main__':
    main()
