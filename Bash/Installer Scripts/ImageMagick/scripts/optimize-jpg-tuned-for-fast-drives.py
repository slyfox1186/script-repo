#!/Usr/bin/env python3


import os
import subprocess
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed
import multiprocessing

def find_jpg_files(directory):
    jpg_files = [path for path in Path(directory).rglob('*.jpg') if '-IM.jpg' not in path.name]
    jpg_files = sorted(jpg_files, key=lambda f: int(''.join(filter(str.isdigit, f.name))))
    return jpg_files

def convert_image(image_path):
    output_path = image_path.parent / f"{image_path.stem}-IM.jpg"
    with open(os.devnull, 'wb') as devnull:
        subprocess.run([
            "convert", str(image_path),
            "-filter", "Triangle",
            "-define", "filter:support=2",
            "-thumbnail", "100%",
            "-strip",
            "-unsharp", "0.25x0.08+8.3+0.045",
            "-dither", "None",
            "-posterize", "136",
            "-quality", "82",
            "-define", "jpeg:fancy-upsampling=off",
            "-auto-level",
            "-enhance",
            "-interlace", "none",
            "-colorspace", "sRGB",
            str(output_path)
        ], stdout=devnull, stderr=devnull)
    os.remove(image_path)
    return image_path.name

def main():
    files = find_jpg_files(directory)
    total_files = len(files)

    print("Starting image conversion...")

    with ProcessPoolExecutor(max_workers=num_processes) as executor:
        for index, future in enumerate(as_completed([executor.submit(convert_image, file) for file in files]), start=1):
            filename = files[index - 1].name
            try:
                result = future.result()
                percent = (index / total_files) * 100
                print(f"Converted: {filename} ({percent:.2f}%)")
            except Exception as e:
                print(f"Error converting file {filename}: {e}")

    print("\nImage conversion completed.")

if __name__ == "__main__":
    main()
