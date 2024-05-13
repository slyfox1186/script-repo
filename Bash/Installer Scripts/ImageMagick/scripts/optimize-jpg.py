#!/usr/bin/env python3

import os
import psutil
from PIL import Image, UnidentifiedImageError
import subprocess
from concurrent.futures import ThreadPoolExecutor

# Increase the maximum number of pixels that can be processed by Pillow.
Image.MAX_IMAGE_PIXELS = None  # Optionally set a specific limit

def process_image(image_path):
    if '-IM.jpg' in image_path:
        print(f"Skipping already processed file: {image_path}")
        return False

    try:
        with Image.open(image_path) as img:
            orig_width, orig_height = img.size
            max_width, max_height = 8000, 6000
            scale = min(max_width / orig_width, max_height / orig_height, 1)
            if scale < 1:
                new_width = int(orig_width * scale)
                new_height = int(orig_height * scale)
                print(f"Resizing {image_path} from {orig_width}x{orig_height} to {new_width}x{new_height}...")
                img = img.resize((new_width, new_height), Image.LANCZOS)
                img.save(image_path, 'JPEG', quality=82)
                print(f"Resized: {image_path}")

        im_output_path = os.path.splitext(image_path)[0] + '-IM.jpg'
        command = [
            'convert', image_path,
            '-unsharp', '0.25x0.08+8.3+0.045',
            '-dither', 'None',
            '-posterize', '136',
            '-quality', '82',
            '-define', 'jpeg:fancy-upsampling=off',
            '-auto-level',
            '-enhance',
            '-interlace', 'none',
            '-colorspace', 'sRGB',
            im_output_path
        ]

        subprocess.run(command, check=True)
        print(f"Processed and saved as: {im_output_path}")
        os.remove(image_path)
        print(f"Removed original file: {image_path}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Failed to process {image_path} with ImageMagick: {e}")
        return False
    except (UnidentifiedImageError, OSError) as e:
        print(f"Skipping corrupt or invalid file: {image_path}. Error: {str(e)}")
        return False
    except Exception as e:
        print(f"An error occurred while processing {image_path}: {e}")
        return False

def process_images(directory):
    images = [os.path.join(directory, f) for f in sorted(os.listdir(directory)) if f.lower().endswith('.jpg') and '-IM.jpg' not in f]
    max_workers = psutil.cpu_count(logical=True) // 2  # Use half of the available CPU cores
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        results = list(executor.map(process_image, images))
    print(f"Processing completed: {sum(results)} images successfully processed.")

def cleanup():
    try:
        current_process = psutil.Process()
        children = current_process.children(recursive=True)
        for child in children:
            if 'convert' in child.name():
                child.terminate()
    except Exception as e:
        print(f"An error occurred during cleanup: {str(e)}")

if __name__ == "__main__":
    script_directory = os.path.dirname(os.path.realpath(__file__))
    process_images(script_directory)
