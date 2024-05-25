#!/usr/bin/env python3
import os
import argparse
import concurrent.futures
import subprocess

def show_help():
    help_text = """
    Usage: find_best_videos.py [OPTION]... DIRECTORY
    Recursively searches the specified DIRECTORY for MP4 files and ranks them by video quality.

    Options:
      -d, --display-values  Include quality values in the output log.
      -h, --help            Display this help message and exit.
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

def main():
    parser = argparse.ArgumentParser(description="Rank MP4 videos by quality.")
    parser.add_argument('directory', metavar='DIRECTORY', type=str, help='Directory to search for MP4 files.')
    parser.add_argument('-d', '--display-values', action='store_true', help='Include quality values in the output log.')
    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        show_help()
        exit(1)

    mp4_files = find_mp4_files(args.directory)
    video_qualities = {}

    with concurrent.futures.ThreadPoolExecutor() as executor:
        futures = [executor.submit(get_video_quality, file) for file in mp4_files]
        for future in concurrent.futures.as_completed(futures):
            file, quality = future.result()
            if file and quality is not None:
                video_qualities[file] = quality

    sorted_videos = sorted(video_qualities.items(), key=lambda x: x[1], reverse=True)

    with open('video_quality_log.txt', 'w') as log_file:
        log_file.write("Video files sorted by quality (best to worst):\n\n")
        for video, quality in sorted_videos:
            if args.display_values:
                log_file.write(f"Weighted Rank: {quality} Path: {video}\n")
            else:
                log_file.write(f"Path: {video}\n")

    print("Log file generated: video_quality_log.txt")

if __name__ == '__main__':
    main()
