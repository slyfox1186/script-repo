#!/usr/bin/env python3

# Made for use with windows WSL

import os
import subprocess
import json
from PIL import Image, UnidentifiedImageError
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# Adjust the pixel limit here if you decide to process larger images
Image.MAX_IMAGE_PIXELS = None # Removes the limit entirely
# Or
# PIXEL_LIMIT = 1000000  # Sets a specific pixel limit
# Image.MAX_IMAGE_PIXELS = PIXEL_LIMIT

output_directory = Path("/tmp")

def find_image_files(directory):
    """Yield file paths to all image files (jpg, jpeg, png, tif) in the specified directory and subdirectories."""
    valid_extensions = (".jpg", ".jpeg", ".png", ".tif")
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.lower().endswith(valid_extensions):
                yield os.path.join(root, file)

def get_max_pixel_density(image_path):
    """Return the max pixel density (width, height, pixel_count) of the image at image_path."""
    try:
        with Image.open(image_path) as img:
            width, height = img.size
            pixel_count = width * height
            return width, height, pixel_count
    except (UnidentifiedImageError, Exception) as e:  # Catch any exception, including decompression bomb warnings/errors
        print(f"Error processing image file: {image_path}. Error: {e}")
        return 0, 0, 0

def save_folder_info(folder_info, filename="folder_info.json"):
    """Save folder information to a JSON file."""
    with open(output_directory / filename, 'w') as file:
        json.dump(folder_info, file)

def load_folder_info(filename="folder_info.json"):
    """Load folder information from a JSON file."""
    try:
        with open(output_directory / filename, 'r') as file:
            return json.load(file)
    except FileNotFoundError:
        print("No existing folder info found. Starting a new scan.")
        return {}

def update_progress_bar(progress, total):
    """Update the progress bar in the console."""
    percent = 100 * (progress / total)
    bar = '#' * int(percent) + '-' * (100 - int(percent))
    print(f"\r[{bar}] {percent:.2f}% Completed", end="")
    if progress == total:
        print()  # Ensure there's a new line after progress completion

def create_and_execute_open_folders_bash_script(folders, viewer_choice, filename="open_folders.sh", delay_seconds=2):
    """Create and execute a bash script to open selected folders with the specified viewer."""
    script_path = output_directory / filename

    viewer_executable = 'fsviewer.exe' if viewer_choice == 'f' else 'explorer.exe'

    with open(script_path, 'w') as file:
        file.write("#!/usr/bin/env bash\n")
        file.write("clear\n")  # Clear the terminal at the beginning of the script
        for folder in folders:
            transformed_path = subprocess.check_output(["wslpath", "-w", folder]).decode().strip()
            transformed_path = transformed_path.replace("\\", "\\\\")
            file.write(f'{viewer_executable} "{transformed_path}" &\n')
            if viewer_executable == 'fsviewer.exe':
                file.write(f'sleep {delay_seconds}\n')

    print(f"Bash script created and executing: {script_path}")
    os.chmod(script_path, 0o755)
    subprocess.run(['bash', str(script_path)])

def parse_folder_selection(selection, max_number):
    """Parse the user's selection input into a set of selected folder indices."""
    selected_folders = set()
    for part in selection.split(','):
        if '-' in part:
            start, end = map(int, part.split('-'))
            selected_folders.update(range(start, end + 1))
        else:
            selected_folders.add(int(part))
    return {n for n in selected_folders if 0 < n <= max_number}

def main():
    """Main function to orchestrate the script's workflow."""
    action = input("Do you want to 'scan' for new files or 'remove' existing files? (scan/remove): ").lower()
    if action == 'remove':
        try:
            os.remove(output_directory / "folder_info.json")
            os.remove(output_directory / "open_folders.sh")
            print("Files removed successfully.")
        except FileNotFoundError:
            print("No files to remove.")
        return

    script_dir = Path(os.getcwd())
    image_files = list(find_image_files(str(script_dir)))

    folder_info = load_folder_info()
    if not folder_info:
        folder_max_density = {}
        with ThreadPoolExecutor() as executor:
            futures = [executor.submit(get_max_pixel_density, path) for path in image_files]
            progress = 0
            total_files = len(image_files)

            for future in as_completed(futures):
                width, height, pixel_count = future.result()
                folder = str(Path(image_files[progress]).parent)
                if (width, height, pixel_count) > folder_max_density.get(folder, (0, 0, 0)):
                    folder_max_density[folder] = (width, height, pixel_count)
                progress += 1
                update_progress_bar(progress, total_files)

        print("\nImage processing completed.")
        save_folder_info(folder_max_density)
    else:
        folder_max_density = folder_info

    # Sort folders by the highest pixel count found in their images, then by max resolution as a tiebreaker
    sorted_folders = sorted(folder_max_density.items(), key=lambda x: (x[1][2], max(x[1][0:2])), reverse=True)

    print("Ranked Folders by Image Quality:")
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
