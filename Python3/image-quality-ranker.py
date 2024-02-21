#!/usr/bin/env python3

import os
import subprocess
import json
from PIL import Image, UnidentifiedImageError
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

Image.MAX_IMAGE_PIXELS = None  # Adjust according to your security considerations

def find_jpg_files(directory):
    return [os.path.join(root, file) for root, dirs, files in os.walk(directory) for file in files if file.endswith(".jpg")]

def get_max_pixel_density(image_path):
    try:
        with Image.open(image_path) as img:
            width, height = img.size
            return image_path, (width, height, width * height)
    except UnidentifiedImageError:
        return image_path, (0, 0, 0)

def save_folder_info(folder_info, filename="folder_info.json"):
    with open(filename, 'w') as file:
        json.dump(folder_info, file)

def load_folder_info(filename="folder_info.json"):
    try:
        with open(filename, 'r') as file:
            return json.load(file)
    except FileNotFoundError:
        return {}  # Return an empty dictionary if the file does not exist

def update_progress_bar(progress, total):
    percent = 100 * (progress / total)
    bar = '#' * int(percent) + '-' * (100 - int(percent))
    print(f"\r[{bar}] {percent:.2f}% Completed", end="")
    if progress == total:
        print()  # Ensure there's a new line after the progress completion

def process_images(jpg_files):
    folder_max_density = {}
    total_files = len(jpg_files)
    progress = 0
    with ThreadPoolExecutor(max_workers=64) as executor:
        future_to_image = {executor.submit(get_max_pixel_density, path): path for path in jpg_files}
        for future in as_completed(future_to_image):
            progress += 1
            update_progress_bar(progress, total_files)
            image_path, (width, height, pixel_count) = future.result()
            folder = str(Path(image_path).parent)
            if (width, height, pixel_count) > folder_max_density.get(folder, (0, 0, 0)):
                folder_max_density[folder] = (width, height, pixel_count)
    print()  # Ensure there's a new line after progress completion
    return folder_max_density

def parse_folder_selection(selection, max_number):
    selected_folders = set()
    for part in selection.split(','):
        if '-' in part:
            start, end = map(int, part.split('-'))
            selected_folders.update(range(start, end + 1))
        else:
            selected_folders.add(int(part))
    return {n for n in selected_folders if 0 < n <= max_number}

def create_and_execute_open_folders_bash_script(folders, viewer_choice, filename="open_folders.sh", delay_seconds=2):
    script_dir = Path(__file__).parent
    script_path = script_dir / filename
    viewer_executable = 'explorer.exe' if viewer_choice == 'e' else 'fsviewer.exe'
    with open(script_path, 'w') as file:
        file.write("#!/usr/bin/env bash\n")
        file.write("clear\n")
        for folder in folders:
            file.write(f'{viewer_executable} "{folder}" &\n')
            file.write(f'sleep {delay_seconds}\n')
    subprocess.run(['bash', str(script_path)], check=True)

def main():
    script_dir = Path(__file__).parent
    jpg_files = find_jpg_files(str(script_dir))
    folder_info = load_folder_info()

    if not folder_info:
        folder_info = process_images(jpg_files)
        print("\nImage processing completed.")
        save_folder_info(folder_info)
    else:
        print("\nLoaded existing folder info.")

    sorted_folders = sorted(folder_info.items(), key=lambda x: x[1][2], reverse=True)
    for i, (folder, (width, height, pixel_count)) in enumerate(sorted_folders, start=1):
        print(f"{i}. {folder} - Max Resolution: {width}x{height}, Pixel Count: {pixel_count}")

    selection_input = input("\nEnter the number(s) of the folder(s) you want to open (e.g., '1,3,5' or '2-4'): ")
    selected_numbers = parse_folder_selection(selection_input, len(sorted_folders))
    selected_folders = [sorted_folders[number - 1][0] for number in selected_numbers]

    viewer_choice = input("Choose the program to open the folders with ('e' for explorer.exe, 'f' for fsviewer.exe): ").lower()
    create_and_execute_open_folders_bash_script(selected_folders, viewerchoice)

if __name__ == "__main__":
    main()
