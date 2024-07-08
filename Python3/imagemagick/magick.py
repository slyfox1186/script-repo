#!/usr/bin/env python3

# Purpose: Uses Machine Learning to generate an optimal command line whose focus is to produce the highest quality image and the smallest file size

import argparse
import concurrent.futures
import csv
import cv2
import logging
import multiprocessing
import numpy as np
import os
import psutil
import random
import sqlite3
import subprocess
import sys
import time
from datetime import datetime
from functools import lru_cache
from PIL import Image
from skimage.metrics import peak_signal_noise_ratio as psnr
from skimage.metrics import structural_similarity as ssim

# User-configurable variables
BEST_COMMANDS_FILE = "best_commands.csv"
COMMAND_DB_FILE = "commands.db"
MAX_WORKERS = multiprocessing.cpu_count()
OUTPUT_FORMAT = "jpg"
TOGGLE_RUN_BEST = "OFF"

# Genetic Algorithm parameters
GENERATIONS = 10
MAX_ATTEMPTS = 10
INITIAL_COMMAND_COUNT = 8
MIN_OPTIONS_PER_COMMAND = 3
MUTATION_RATE = 0.2
POPULATION_SIZE = INITIAL_COMMAND_COUNT
QUALITY_RANGE = (82, 91)
REFINEMENT_FACTOR = 2

# QUALITY THRESHOLD
PSNR_THRESHOLD = 40
SSIM_THRESHOLD = 0.96

logging.basicConfig(level=logging.INFO, format='%(message)s')

def print_configuration():
    print()
    logging.info("User-configurable variables:")
    logging.info(f"INITIAL_COMMAND_COUNT: {INITIAL_COMMAND_COUNT}")
    logging.info(f"MAX_WORKERS: {MAX_WORKERS}")
    logging.info(f"QUALITY_RANGE: {QUALITY_RANGE}")
    logging.info(f"MIN_OPTIONS_PER_COMMAND: {MIN_OPTIONS_PER_COMMAND}")
    logging.info(f"REFINEMENT_FACTOR: {REFINEMENT_FACTOR}")
    logging.info(f"OUTPUT_FORMAT: {OUTPUT_FORMAT}")
    logging.info(f"BEST_COMMANDS_FILE: {BEST_COMMANDS_FILE}\n")
    logging.info("Genetic Algorithm parameters:")
    logging.info(f"POPULATION_SIZE: {POPULATION_SIZE}")
    logging.info(f"GENERATIONS: {GENERATIONS}")
    logging.info(f"MAX_ATTEMPTS: {MAX_ATTEMPTS}")
    logging.info(f"MUTATION_RATE: {MUTATION_RATE}\n")
    logging.info("Quality Thresholds:")
    logging.info(f"PSNR_THRESHOLD: {PSNR_THRESHOLD}")
    logging.info(f"SSIM_THRESHOLD: {SSIM_THRESHOLD}\n")

def detect_noise(image_path):
    image = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    return cv2.Laplacian(image, cv2.CV_64F).var() if image is not None else 0

def initialize_db():
    conn = sqlite3.connect(COMMAND_DB_FILE)
    cursor = conn.cursor()
    cursor.execute('''CREATE TABLE IF NOT EXISTS commands
                      (id INTEGER PRIMARY KEY, command TEXT, UNIQUE(command))''')
    conn.commit()
    return conn, cursor

def add_commands_to_db(cursor, commands):
    cursor.executemany("INSERT OR IGNORE INTO commands (command) VALUES (?)",
                       [(cmd,) for cmd in commands])

def check_commands_in_db(cursor, commands):
    placeholders = ','.join('?' * len(commands))
    cursor.execute(f"SELECT command FROM commands WHERE command IN ({placeholders})", commands)
    return set(row[0] for row in cursor.fetchall())

@lru_cache(maxsize=None)
def get_sampling_factor(input_file):
    try:
        identify_command = f"identify -format '%[jpeg:sampling-factor]' {input_file}"
        sampling_factor = subprocess.check_output(identify_command, shell=True).decode('utf-8').strip()
        return sampling_factor if sampling_factor in ["4:2:0", "4:2:2", "4:4:4"] else "4:2:0"
    except subprocess.CalledProcessError:
        return "4:2:0"

def run_imagemagick_command(args):
    input_file, output_file, command, num_threads = args
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    full_command = f"magick -limit thread {num_threads} {input_file} {command} {output_file}"
    try:
        subprocess.run(full_command, shell=True, check=True, stderr=subprocess.PIPE, text=True, timeout=300)
        return True
    except:
        return False

def analyze_image(args):
    input_file, output_file = args
    try:
        with Image.open(input_file) as original_image, Image.open(output_file) as compressed_image:
            compressed_size = os.path.getsize(output_file)
            if original_image.size != compressed_image.size:
                original_image = original_image.resize(compressed_image.size, Image.LANCZOS)

            original_array = np.array(original_image)
            compressed_array = np.array(compressed_image)

            psnr_value = psnr(original_array, compressed_array)
            ssim_value = ssim(original_array, compressed_array, channel_axis=-1 if original_array.ndim > 2 else None)
            noise_level = detect_noise(output_file)

            print()
            logging.info(f"Image: {os.path.basename(output_file)}")
            logging.info(f"Size: {compressed_size / 1024:.1f} KB")
            logging.info(f"PSNR: {psnr_value:.2f}, SSIM: {ssim_value:.4f}, Noise: {noise_level:.2f}")
            logging.info(f"Quality: {'Acceptable' if psnr_value >= PSNR_THRESHOLD and ssim_value >= SSIM_THRESHOLD and noise_level <= 100 else 'Not Acceptable'}")

            return compressed_size, compressed_image.size, psnr_value, ssim_value, noise_level
    except Exception as e:
        logging.error(f"Error analyzing image: {output_file}. Error message: {str(e)}")
        return None

def mutate_command(command, noise_level, target_size):
    parts = command.split()
    for i, part in enumerate(parts):
        if part == "-quality":
            quality = int(parts[i + 1])
            if noise_level > 50:
                # If noise level is medium or higher, reduce the quality to combat noise
                if noise_level > 100:
                    # If noise level is high, reduce quality more aggressively
                    new_quality = max(QUALITY_RANGE[0], min(QUALITY_RANGE[1], quality - 10))
                else:
                    new_quality = max(QUALITY_RANGE[0], min(QUALITY_RANGE[1], quality - 5))
            else:
                new_quality = max(QUALITY_RANGE[0], min(QUALITY_RANGE[1], quality + random.choice([-1, 1])))
            parts[i + 1] = str(new_quality)
        elif part in ["-unsharp", "-adaptive-sharpen"]:
            if random.random() < MUTATION_RATE:
                values = parts[i + 1].split('+' if part == "-unsharp" else 'x')
                new_values = []
                for v in values:
                    if 'x' in v:
                        subvalues = v.split('x')
                        if noise_level > 50:
                            # If noise level is medium or higher, reduce the unsharp/adaptive-sharpen values to combat noise
                            if noise_level > 100:
                                # If noise level is high, reduce unsharp/adaptive-sharpen more aggressively
                                new_subvalues = [str(max(0, min(10, float(sv) - 0.1))) for sv in subvalues]
                            else:
                                new_subvalues = [str(max(0, min(10, float(sv) - 0.05))) for sv in subvalues]
                        else:
                            new_subvalues = [str(max(0, min(10, float(sv) + random.uniform(-0.01, 0.01)))) for sv in subvalues]
                        new_values.append('x'.join(new_subvalues))
                    else:
                        if noise_level > 50:
                            # If noise level is medium or higher, reduce the unsharp/adaptive-sharpen values to combat noise
                            if noise_level > 100:
                                # If noise level is high, reduce unsharp/adaptive-sharpen more aggressively
                                new_values.append(str(max(0, min(10, float(v) - 0.1))))
                            else:
                                new_values.append(str(max(0, min(10, float(v) - 0.05))))
                        else:
                            new_values.append(str(max(0, min(10, float(v) + random.uniform(-0.01, 0.01)))))
                parts[i + 1] = ('+' if part == "-unsharp" else 'x').join(new_values)
        elif part == "-define":
            if parts[i + 1].startswith("jpeg:extent="):
                parts[i + 1] = f"jpeg:extent={target_size}b"
    return ' '.join(parts)

def generate_imagemagick_commands(input_file, count, target_size):
    commands = []
    sampling_factor = get_sampling_factor(input_file)
    for _ in range(count):
        quality = random.randint(40, 80)
        unsharp = f"{np.random.uniform(0, 1):.2f}x{np.random.uniform(0, 1):.2f}+{np.random.uniform(0, 5):.1f}+{np.random.uniform(0, 0.05):.3f}"
        adaptive_sharpen = f"{np.random.uniform(0, 2):.1f}x{np.random.uniform(0, 0.5):.1f}"
        posterize = np.random.randint(64, 256)
        command = f"-strip -define jpeg:dct-method=float -interlace Plane -colorspace sRGB -filter Lanczos -define filter:blur=0.9891028367558475 -define filter:window=Jinc -define filter:lobes=3 -sampling-factor {sampling_factor} -quality {quality} -unsharp {unsharp} -adaptive-sharpen {adaptive_sharpen} -posterize {posterize} -define jpeg:extent={target_size}b"
        commands.append(command)
    return commands

def process_commands(input_file, commands, output_directory, log_file, target_size):
    num_threads = max(1, MAX_WORKERS // len(commands))
    with multiprocessing.Pool(MAX_WORKERS) as pool:
        run_args = [(input_file, f"{output_directory}/output_{i:02d}.{OUTPUT_FORMAT}", cmd, num_threads) for i, cmd in enumerate(commands)]
        results = pool.map(run_imagemagick_command, run_args)

        analyze_args = [(input_file, f"{output_directory}/output_{i:02d}.{OUTPUT_FORMAT}") for i, success in enumerate(results) if success]
        analysis_results = pool.map(analyze_image, analyze_args)

    successful_commands = []
    with open(log_file, "a", newline="") as file:
        writer = csv.writer(file)
        for cmd, result in zip(commands, analysis_results):
            if result is not None:
                file_size, dimensions, psnr_value, ssim_value, noise_level = result
                writer.writerow([cmd, file_size, dimensions[0], dimensions[1], psnr_value, ssim_value, noise_level])
                if file_size <= target_size and psnr_value >= PSNR_THRESHOLD and ssim_value >= SSIM_THRESHOLD and noise_level <= 100:
                    successful_commands.append((cmd, psnr_value, ssim_value, file_size))

    return successful_commands

def get_smallest_image_size(directory):
    if not os.path.exists(directory):
        return None

    min_size = float('inf')
    for file in os.listdir(directory):
        file_path = os.path.join(directory, file)
        if os.path.isfile(file_path) and file.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tiff', '.webp')):
            file_size = os.path.getsize(file_path)
            if file_size < min_size:
                min_size = file_size
    return min_size if min_size != float('inf') else None

def get_target_size(input_file, optimal_directory):
    smallest_size = get_smallest_image_size(optimal_directory)
    input_size = os.path.getsize(input_file)

    if smallest_size is not None:
        target_size = min(smallest_size, input_size * 0.9)
    else:
        target_size = input_size * 0.9

    return int(target_size * 0.95)

def check_and_kill_existing_processes():
    current_pid = os.getpid()
    killed_processes = []
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if proc.info['cmdline'] is None or not isinstance(proc.info['cmdline'], list):
                continue
            cmdline = ' '.join(proc.info['cmdline'])
            if proc.info['pid'] != current_pid and \
               (proc.info['name'] == 'magick' or 'python3' in proc.info['name']) and \
               ('magick' in cmdline or 'magick.py' in cmdline):
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except psutil.TimeoutExpired:
                    proc.kill()
                killed_processes.append(proc.info['pid'])
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
        except Exception as e:
            logging.error(f"Error handling process: {str(e)}")

    os.system('clear' if os.name == 'posix' else 'cls')

    if killed_processes:
        logging.info(f"Cleaned up {len(killed_processes)} existing processes: {', '.join(map(str, killed_processes))}")
        print()
    else:
        logging.info("No existing processes found to clean up.")
        print()

def validate_command(command):
    command_parts = command.split()
    i = 0
    while i < len(command_parts):
        if command_parts[i] in ["-strip"]:
            i += 1
            continue
        elif command_parts[i] in ["-filter", "-define", "-dither", "-posterize", "-interlace", "-colorspace", "-sampling-factor", "-quality", "-unsharp", "-adaptive-sharpen"]:
            if i + 1 >= len(command_parts) or command_parts[i + 1].startswith('-'):
                logging.error(f"Missing argument for {command_parts[i]}")
                return False
            i += 2
        else:
            logging.error(f"Invalid command part: {command_parts[i]}")
            return False
    return True

def optimize_stored_commands(input_file, output_directory, stored_commands):
    initial_population = []
    for command in stored_commands:
        individual = {}
        options = command.split()
        for i, option in enumerate(options):
            if option == "-quality":
                individual["quality"] = int(options[i+1])
            elif option == "-unsharp":
                individual["unsharp"] = options[i+1]
            elif option == "-adaptive-sharpen":
                individual["adaptive-sharpen"] = options[i+1]
        if len(individual) == 3:
            initial_population.append(individual)

    while len(initial_population) < POPULATION_SIZE:
        initial_population.append(create_individual())

    return generate_imagemagick_commands(input_file, len(initial_population))

def create_full_commands_script(best_commands, input_file):
    script_content = "#!/bin/bash\n\n"
    script_content += "# This script contains the optimal ImageMagick commands\n\n"

    for i, command in enumerate(best_commands, 1):
        output_file = f"optimized_output_{i}.jpg"
        full_command = f"magick \"{input_file}\" {command} \"{output_file}\"\n"
        script_content += f"echo \"Executing optimal command {i}...\"\n"
        script_content += full_command
        script_content += f"echo \"Saved result as {output_file}\"\n\n"

    script_content += "echo \"All optimal commands have been executed.\"\n"

    with open("full-commands.sh", "w") as file:
        file.write(script_content)

    os.chmod("full-commands.sh", 0o755)  # Make the script executable

def clean_temp_files(directory):
    for file in os.listdir(directory):
        file_path = os.path.join(directory, file)
        if os.path.isfile(file_path) and file.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tiff', '.webp')):
            os.remove(file_path)
            logging.info(f"Deleted temporary file: {file_path}")

def main():
    parser = argparse.ArgumentParser(description="Optimize ImageMagick commands for image compression.")
    parser.add_argument('-i', '--input', required=True, help='Input image file')
    parser.add_argument('-o', '--output', default="temp-files", help='Output directory')
    parser.add_argument('-l', '--log', default="optimization_log.csv", help='Log file name')
    args = parser.parse_args()

    check_and_kill_existing_processes()

    input_file = args.input
    output_directory = args.output
    log_file = args.log
    optimal_directory = "optimal-images"

    os.makedirs(output_directory, exist_ok=True)
    clean_temp_files(output_directory)

    target_size = get_target_size(input_file, optimal_directory)
    logging.info(f"Adjusted target size with safety margin: {target_size / 1024:.2f} KB")
    print_configuration()

    conn, cursor = initialize_db()

    start_time = datetime.now()

    if TOGGLE_RUN_BEST == "ON":
        # Use the best command lines from the CSV file
        best_commands = []
        if os.path.exists(BEST_COMMANDS_FILE):
            with open(BEST_COMMANDS_FILE, "r") as file:
                reader = csv.reader(file)
                best_commands = [row[1] for row in reader if len(row) > 1]

        if best_commands:
            logging.info(f"Using {len(best_commands)} best command lines from {BEST_COMMANDS_FILE}.")
            commands = best_commands
            existing_commands = check_commands_in_db(cursor, commands)
            new_commands = [cmd for cmd in commands if cmd not in existing_commands and validate_command(cmd)]
        else:
            logging.warning(f"No best command lines found in {BEST_COMMANDS_FILE}. Generating new commands.")
            commands = generate_imagemagick_commands(input_file, INITIAL_COMMAND_COUNT, target_size)
            existing_commands = check_commands_in_db(cursor, commands)
            new_commands = [cmd for cmd in commands if cmd not in existing_commands and validate_command(cmd)]
    else:
        # Generate new commands
        logging.info("Generating new commands.")
        commands = generate_imagemagick_commands(input_file, INITIAL_COMMAND_COUNT, target_size)
        existing_commands = check_commands_in_db(cursor, commands)
        new_commands = [cmd for cmd in commands if cmd not in existing_commands and validate_command(cmd)]

    best_command = None
    for attempt in range(MAX_ATTEMPTS):
        logging.info(f"\nAttempt {attempt + 1} of {MAX_ATTEMPTS}")
        successful_commands = []
        for generation in range(GENERATIONS):
            logging.info(f"Generation {generation + 1} of {GENERATIONS}")
            successful_commands = process_commands(input_file, new_commands, output_directory, log_file, target_size)

            if successful_commands:
                best_command = max(successful_commands, key=lambda x: (x[1], x[2], -x[3]))
                logging.info(f"Best command found: {best_command[0]}")
                break
            else:
                logging.info("No successful commands found. Generating new commands.")
                noise_level = detect_noise(input_file)
                new_commands = [mutate_command(cmd, noise_level, target_size) for cmd in new_commands]

        if best_command is not None:
            break

    if best_command is None:
        logging.error("Failed to find a suitable command after all attempts.")
        return

    logging.info(f"\nOptimization completed in {datetime.now() - start_time}")
    logging.info(f"Best command: {best_command[0]}")
    logging.info(f"PSNR: {best_command[1]:.2f}")
    logging.info(f"SSIM: {best_command[2]:.4f}")
    logging.info(f"File size: {best_command[3] / 1024:.2f} KB")

    with open(BEST_COMMANDS_FILE, "a", newline="") as file:
        writer = csv.writer(file)
        writer.writerow([datetime.now().strftime("%Y-%m-%d %H:%M:%S"), best_command[0]])

    add_commands_to_db(cursor, [best_command[0]])
    conn.commit()
    conn.close()

    create_full_commands_script([best_command[0]], input_file)

    optimized_output = f"optimized_{os.path.splitext(os.path.basename(input_file))[0]}.{OUTPUT_FORMAT}"
    run_imagemagick_command((input_file, optimized_output, best_command[0], multiprocessing.cpu_count()))
    logging.info(f"Optimized image saved as {optimized_output}")

if __name__ == "__main__":
    main()
