#!/usr/bin/env python3

import os
import subprocess
import json
from PIL import Image, UnidentifiedImageError
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# This script recursively searches for all JPG images in its directory.
# Then, it ranks the images based on their DPI and size, listing them according to their quality.

def find_jpg_files(directory):
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith(".jpg"):
                yield os.path.join(root, file)

def get_max_pixel_density(image_path):
    try:
        with Image.open(image_path) as img:
            width, height = img.size
            pixel_count = width * height
            return width, height, pixel_count
    except UnidentifiedImageError:
        print(f"Cannot identify image file: {image_path}")
        return 0, 0, 0

def save_folder_info(folder_info, filename="folder_info.json"):
    with open(filename, 'w') as file:
        json.dump(folder_info, file)

def load_folder_info(filename="folder_info.json"):
    try:
        with open(filename, 'r') as file:
            return json.load(file)
    except FileNotFoundError:
        return {}

def update_progress_bar(progress, total):
    percent = 100 * (progress / total)
    bar = '#' * int(percent) + '-' * (100 - int(percent))
    print(f"\r[{bar}] {percent:.2f}% Completed", end="")

def create_and_execute_open_folders_bash_script(folders, viewer_choice, filename="open_folders.sh", delay_seconds=2):
    script_dir = Path(os.path.dirname(os.path.realpath(__file__)))
    script_path = script_dir / filename

    # Replace 'f' with 'fsviewer.exe' and 'e' with 'explorer.exe'
    viewer_executable = 'fsviewer.exe' if viewer_choice == 'f' else 'explorer.exe'

    with open(script_path, 'w') as file:
        file.write("#!/usr/bin/env bash\n")
        for folder in folders:
            transformed_path = subprocess.check_output(["wslpath", "-w", folder]).decode().strip()
            transformed_path = transformed_path.replace("\\", "\\\\")
            file.write(f'{viewer_executable} "{transformed_path}" &\n')
            if viewer_executable == 'fsviewer.exe':
                # Add a delay for fsviewer.exe
                file.write(f'sleep {delay_seconds}\n')
    
    print(f"Bash script created and executing: {script_path}")
    os.chmod(script_path, 0o755)
    subprocess.run([str(script_path)])

def parse_folder_selection(selection, max_number):
    selected_folders = set()
    for part in selection.split(','):
        if '-' in part:
            start, end = map(int, part.split('-'))
            selected_folders.update(range(start, end + 1))
        else:
            selected_folders.add(int(part))
    return {n for n in selected_folders if 0 < n <= max_number}

def main():
    script_dir = Path(os.path.dirname(os.path.realpath(__file__)))
    jpg_files = list(find_jpg_files(str(script_dir)))

    folder_info = load_folder_info()
    if not folder_info:
        folder_max_density = {}
        with ThreadPoolExecutor() as executor:
            futures = [executor.submit(get_max_pixel_density, path) for path in jpg_files]
            progress = 0
            total_files = len(jpg_files)

            for future in as_completed(futures):
                width, height, pixel_count = future.result()
                folder = str(Path(jpg_files[progress]).parent)
                if (width, height, pixel_count) > folder_max_density.get(folder, (0, 0, 0)):
                    folder_max_density[folder] = (width, height, pixel_count)
                progress += 1
                update_progress_bar(progress, total_files)

        print("\nImage processing completed.")
        save_folder_info(folder_max_density)
    else:
        folder_max_density = folder_info

    sorted_folders = sorted(folder_max_density.items(), key=lambda x: (x[1][2], max(x[1][0:2])), reverse=True)

    for i, (folder, (width, height, pixel_count)) in enumerate(sorted_folders, start=1):
        print(f"{i}. {folder} - Max Resolution: {width}x{height}, Pixel Count: {pixel_count}")

    selection_input = input("\nEnter the number(s) of the folder(s) you want to open (e.g., '1-5', '1,4,7'): ")
    selected_numbers = parse_folder_selection(selection_input, len(sorted_folders))
    selected_folders = [sorted_folders[number - 1][0] for number in selected_numbers]

    viewer_choice = input("Choose the program to open the folders with (enter 'e' for explorer.exe or 'f' for fsviewer.exe): ").lower()
    if viewer_choice not in ['e', 'f']:
        viewer_choice = 'e'

    create_and_execute_open_folders_bash_script(selected_folders, viewer_choice)

if __name__ == "__main__":
    main()
