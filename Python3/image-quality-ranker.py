#!/usr/bin/env python3

# Made for use with Windows WSL

import os
import subprocess
import json
from PIL import Image, UnidentifiedImageError
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# Configuration and setup
Image.MAX_IMAGE_PIXELS = None
output_directory = Path("/tmp")
valid_extensions = (".jpg", ".jpeg", ".png", ".tif", ".gif", ".bmp")

def normalize_input(input_str):
    mappings = {
        'yes': 'yes', 'y': 'yes',
        'no': 'no', 'n': 'no',
        'scan': 'scan', 's': 'scan',
        'remove': 'remove', 'r': 'remove'
    }
    return mappings.get(input_str.lower(), input_str)

def find_image_files(directory):
    for root, _, files in os.walk(directory):
        for file in files:
            if file.lower().endswith(valid_extensions):
                yield os.path.join(root, file)

def get_image_details(image_path):
    try:
        with Image.open(image_path) as img:
            width, height = img.size
            pixel_count = width * height
            return image_path, width, height, pixel_count
    except (UnidentifiedImageError, Exception) as e:
        print(f"Error processing image file: {image_path}. Error: {e}")
        return image_path, 0, 0, 0

def save_folder_info(folder_info, filename="folder_info.json"):
    with open(output_directory / filename, 'w') as file:
        json.dump(folder_info, file)

def load_folder_info(filename="folder_info.json"):
    try:
        with open(output_directory / filename, 'r') as file:
            return json.load(file)
    except FileNotFoundError:
        print("No existing folder info found. Starting a new scan.")
        return {}

def update_progress_bar(progress, total):
    percent = 100 * (progress / total)
    bar = '#' * int(percent) + '-' * (100 - int(percent))
    print(f"\r[{bar}] {percent:.2f}% Completed", end="")
    if progress == total:
        print()

def parse_selection(selection, items):
    selected_indices = []
    for part in selection.split(','):
        if '-' in part:
            start, end = map(int, part.split('-'))
            selected_indices.extend(range(start-1, end))
        else:
            selected_indices.append(int(part)-1)
    return [items[i] for i in selected_indices if 0 <= i < len(items)]

def create_and_execute_open_folders_bash_script(paths, viewer_choice):
    script_content = "#!/usr/bin/env bash\n"
    script_content += "clear\n"
    for path in paths:
        transformed_path = subprocess.check_output(["wslpath", "-w", path]).decode().strip().replace("\\", "\\\\")
        if viewer_choice == 'f':
            script_content += f'fsviewer.exe "{transformed_path}" &\n'
        else:
            script_content += f'start explorer "{transformed_path}"\n'
    script_path = output_directory / "open_with_viewer.sh"
    with open(script_path, 'w') as script_file:
        script_file.write(script_content)
    os.chmod(script_path, 0o755)
    subprocess.run(['bash', str(script_path)], check=True)

def main():
    action = normalize_input(input("Do you want to 'scan' for new files or 'remove' existing files? (scan/remove): "))
    if action == 'remove' or action == 'r':
        try:
            os.remove(output_directory / "folder_info.json")
            print("Folder info and temporary files removed successfully.")
        except FileNotFoundError:
            print("No temporary files to remove.")
        return
    
    include_images = normalize_input(input("Include individual images in results? (yes/no): ")) == 'yes'
    num_images_to_rank = int(input("How many top ranked images do you want to display?: ")) if include_images else 0

    directory = str(Path.cwd())
    image_files = list(find_image_files(directory))
    folder_info = load_folder_info() or {}
    image_quality_info = []

    with ThreadPoolExecutor(max_workers=32) as executor:
        futures = list(executor.map(get_image_details, image_files))
        total = len(futures)
        progress = 0
        for result in futures:
            image_path, width, height, pixel_count = result
            folder = str(Path(image_path).parent)
            if folder not in folder_info or pixel_count > folder_info[folder].get('max_pixel_count', 0):
                folder_info[folder] = {'path': folder, 'width': width, 'height': height, 'max_pixel_count': pixel_count}
            if include_images:
                image_quality_info.append((image_path, pixel_count))
            progress += 1
            update_progress_bar(progress, total)

    save_folder_info(folder_info)

    ranked_folders = sorted(folder_info.values(), key=lambda x: x['max_pixel_count'], reverse=True)
    print("\nRanked Folders by Image Quality:")
    for i, info in enumerate(ranked_folders, start=1):
        print(f"{i}. {info['path']} - Max Resolution: {info['width']}x{info['height']}, Pixel Count: {info['max_pixel_count']}")

    folder_selection_input = input("Enter the number(s) of the folder(s) you want to open (e.g., '1-5', '1,4,7'): ")
    selected_folders = parse_selection(folder_selection_input, ranked_folders)
    folder_viewer_choice = normalize_input(input("Choose the program to open the folders with ('e' for explorer.exe, 'f' for fsviewer.exe): "))
    selected_folder_paths = [info['path'] for info in selected_folders]
    create_and_execute_open_folders_bash_script(selected_folder_paths, folder_viewer_choice)

    if include_images:
        ranked_images = sorted(image_quality_info, key=lambda x: x[1], reverse=True)[:num_images_to_rank]
        print("\nRanked Individual Images by Quality:")
        for i, (path, pixel_count) in enumerate(ranked_images, start=1):
            print(f"{i}. {path} - Pixels: {pixel_count}")

        image_selection_input = input("Enter the number(s) of the image(s) you want to open (e.g., '1,2,3'): ")
        selected_images = parse_selection(image_selection_input, ranked_images)
        selected_image_paths = [path for path, _ in selected_images]
        create_and_execute_open_folders_bash_script(selected_image_paths, folder_viewer_choice)

if __name__ == "__main__":
    main()

