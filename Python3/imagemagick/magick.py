#!/usr/bin/env python3

# Purpose: Uses Machine Learning to generate an optimal command line whose focus is to produce the highest quality image and the smallest file size.

import concurrent.futures
import csv
import cv2
import logging
import multiprocessing
import numpy as np
import os
import psutil
import random
import signal
import sqlite3
import subprocess
import sys
import time
from datetime import datetime
from PIL import Image
from scipy import ndimage
from skimage import io, color, restoration
from skimage.metrics import peak_signal_noise_ratio as psnr
from skimage.metrics import structural_similarity as ssim

# User-configurable variables
NUM_CPUS = multiprocessing.cpu_count()
MAX_WORKERS = NUM_CPUS if NUM_CPUS is not None else 1
OUTPUT_FORMAT = "jpg"
BEST_COMMANDS_FILE = "best_commands.csv"

# Genetic Algorithm parameters
QUALITY_RANGE = (82, 91)
MIN_OPTIONS_PER_COMMAND = 3
REFINEMENT_FACTOR = 2
INITIAL_COMMAND_COUNT = 8
POPULATION_SIZE = INITIAL_COMMAND_COUNT
GENERATIONS = 10
MUTATION_RATE = 0.2
MAX_ATTEMPTS = 10

# QUALITY THRESHOLD
MAX_NOISE_LEVEL = 0.15
PSNR_THRESHOLD = 35
SSIM_THRESHOLD = 0.94

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(message)s')

def initialize_database():
    conn = sqlite3.connect('commands.db')
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS commands
                 (command TEXT PRIMARY KEY, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)''')
    conn.commit()
    conn.close()

def command_exists(command):
    conn = sqlite3.connect('commands.db')
    c = conn.cursor()
    c.execute("SELECT 1 FROM commands WHERE command = ?", (command,))
    exists = c.fetchone() is not None
    conn.close()
    return exists

def add_command(command):
    conn = sqlite3.connect('commands.db')
    c = conn.cursor()
    try:
        c.execute("INSERT INTO commands (command) VALUES (?)", (command,))
        conn.commit()
    except sqlite3.IntegrityError:
        # Command already exists, do nothing
        pass
    finally:
        conn.close()

def measure_noise(image_path):
    # Load the image
    image = io.imread(image_path)

    # Convert to grayscale if the image is in color
    if len(image.shape) == 3:
        image = color.rgb2gray(image)

    # Estimate noise using the mean absolute deviation of the Laplacian
    laplacian = ndimage.laplace(image)
    noise_estimate = np.mean(np.abs(laplacian))

    # Normalize the noise estimate to a 0-1 range
    # This normalization factor may need adjustment based on your specific use case
    normalized_noise = noise_estimate / 0.1

    return min(normalized_noise, 1.0)  # Ensure the result is in [0, 1]

def create_optimization_report(best_command, log_file, target_size):
    with open("optimization_report.txt", "w") as file:
        file.write(f"Optimal ImageMagick command: {best_command}\n\n")
        file.write("This command was selected as the best based on the following criteria:\n")
        file.write("1. Highest PSNR value, indicating minimal loss of image quality.\n")
        file.write("2. Highest SSIM value, indicating preservation of structural similarity.\n")
        file.write("3. Smallest file size, achieving the best compression.\n")
        file.write(f"The optimization process prioritized image quality (PSNR and SSIM) while minimizing file size below {target_size/1024:.2f} KB.\n\n")
        file.write("Runner-up commands:\n")
        with open(log_file, "r") as log:
            reader = csv.reader(log)
            next(reader)  # Skip header
            for row in reader:
                if row[0] != best_command:
                    file.write(f"- {row[0]}\n")
        file.write("\nThese commands also performed well but were slightly inferior in terms of PSNR, SSIM, or file size compared to the optimal command.")
    logging.info("Optimization report created: optimization_report.txt")

def set_magick_limits(input_file):
    try:
        with Image.open(input_file) as img:
            width, height = img.size
        max_dimension = max(width, height)
        area = width * height

        memory_limit = max(1024, min(area // 1000000 * 256, 8192))  # MB
        disk_limit = memory_limit * 4  # MB
        area_limit = area * 4  # pixels
        width_height_limit = max_dimension * 2  # pixels

        magick_limits = {
            'MAGICK_AREA_LIMIT': f'{area_limit}',
            'MAGICK_DISK_LIMIT': f'{disk_limit}MB',
            'MAGICK_MEMORY_LIMIT': f'{memory_limit}MB',
            'MAGICK_WIDTH_LIMIT': f'{width_height_limit}',
            'MAGICK_HEIGHT_LIMIT': f'{width_height_limit}',
            'MAGICK_THREAD_LIMIT': str(MAX_WORKERS),
        }

        logging.info("Set ImageMagick limits:")
        for key, value in magick_limits.items():
            logging.info(f"{key}: {value}")

        print()

        os.environ.update(magick_limits)
    except Exception as e:
        logging.error(f"Error setting ImageMagick limits: {str(e)}")
        default_limits = {
            'MAGICK_AREA_LIMIT': '128MB',
            'MAGICK_DISK_LIMIT': '1GB',
            'MAGICK_MEMORY_LIMIT': '256MB',
            'MAGICK_WIDTH_LIMIT': '16KP',
            'MAGICK_HEIGHT_LIMIT': '16KP',
            'MAGICK_THREAD_LIMIT': str(MAX_WORKERS),
        }
        os.environ.update(default_limits)
        logging.info("Set default ImageMagick limits:")
        for key, value in default_limits.items():
            logging.info(f"{key}: {value}")

def run_imagemagick_command(input_file, output_file, command):
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    full_command = f"magick {input_file} {command} {output_file}"
    try:
        result = subprocess.run(full_command, shell=True, check=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE, text=True, timeout=300)
        logging.debug(f"Command executed successfully: {os.path.basename(output_file)}")
        logging.debug(f"Command output: {result.stdout}")
        logging.debug(f"Command stderr: {result.stderr}")
        return True
    except subprocess.CalledProcessError as e:
        logging.error(f"Error executing: {os.path.basename(output_file)}. Error message: {e.stderr}")
        return False
    except subprocess.TimeoutExpired:
        logging.error(f"Timeout executing: {os.path.basename(output_file)}")
        return False
    except Exception as e:
        logging.error(f"Unexpected error executing command for {os.path.basename(output_file)}: {str(e)}")
        return False

def analyze_image(input_file, output_file):
    try:
        with Image.open(input_file) as original_image, Image.open(output_file) as compressed_image:
            compressed_size = os.path.getsize(output_file)
            if original_image.size != compressed_image.size:
                original_image = original_image.resize(compressed_image.size, Image.LANCZOS)

            original_array = np.array(original_image)
            compressed_array = np.array(compressed_image)

            psnr_value = psnr(original_array, compressed_array)
            ssim_value = ssim(original_array, compressed_array, channel_axis=-1 if original_array.ndim > 2 else None)
            
            # Calculate noise level
            noise_level = detect_noise(output_file)

            return compressed_size, compressed_image.size, psnr_value, ssim_value, noise_level
    except Exception as e:
        logging.error(f"Error analyzing image: {output_file}. Error message: {str(e)}")
        return None

def create_individual():
    return {
        "unsharp": f"{np.random.uniform(0, 1):.2f}x{np.random.uniform(0, 1):.2f}+{np.random.uniform(0, 5):.1f}+{np.random.uniform(0, 0.05):.3f}",
        "adaptive-sharpen": f"{np.random.uniform(0, 2):.1f}x{np.random.uniform(0, 0.5):.1f}",
        "quality": np.random.randint(QUALITY_RANGE[0], QUALITY_RANGE[1] + 1),
        "posterize": np.random.randint(64, 256)
    }

def generate_new_generation(successful_commands, population_size, target_size):
    new_generation = []
    while len(new_generation) < population_size:
        parent1, parent2 = random.sample(successful_commands, 2)
        child = crossover(parent1[0], parent2[0])
        child = mutate(child, target_size)
        new_generation.append(child)
    return new_generation

def crossover(command1, command2):
    parts1 = command1.split()
    parts2 = command2.split()
    child_parts = []
    for p1, p2 in zip(parts1, parts2):
        if random.random() < 0.5:
            child_parts.append(p1)
        else:
            child_parts.append(p2)
    return ' '.join(child_parts)

def mutate(command, target_size):
    parts = command.split()
    for i, part in enumerate(parts):
        if random.random() < MUTATION_RATE:
            if part.startswith('-quality'):
                parts[i+1] = str(random.randint(QUALITY_RANGE[0], QUALITY_RANGE[1]))
            elif part.startswith('-unsharp') or part.startswith('-adaptive-sharpen'):
                values = [float(x) for x in parts[i+1].split('x')]
                mutated_values = [max(0, min(v + random.gauss(0, 0.1), 2)) for v in values]
                parts[i+1] = f"{mutated_values[0]:.2f}x{mutated_values[1]:.2f}"
    parts.append(f"-define jpeg:extent={target_size}b")
    return ' '.join(parts)

def fitness(input_file, output_file, output_directory, max_acceptable_size):
    try:
        result = analyze_image(input_file, os.path.join(output_directory, output_file))
        if result is not None:
            file_size, _, psnr_value, ssim_value = result
            original_size = os.path.getsize(input_file)
            size_reduction = (original_size - file_size) / original_size

            if max_acceptable_size is not None and file_size > max_acceptable_size:
                return -float('inf'), file_size, False

            if psnr_value < PSNR_THRESHOLD or ssim_value < SSIM_THRESHOLD:
                return -float('inf'), file_size, False  # Indicate unacceptable quality

            # Calculate noise level
            noise_level = measure_noise(os.path.join(output_directory, output_file))

            if noise_level > MAX_NOISE_LEVEL:
                return -float('inf'), file_size, False  # Penalize excessive noise

            # Balanced fitness score with emphasis on SSIM and inverse of noise level
            fitness_score = (0.3 * psnr_value) + (0.4 * ssim_value) + (0.2 * size_reduction) + (0.1 * (1 - noise_level/MAX_NOISE_LEVEL))
            return fitness_score, file_size, True
        else:
            return -float('inf'), float('inf'), False
    except Exception as e:
        logging.error(f"Error in fitness evaluation: {str(e)}")
        return -float('inf'), float('inf'), False

# Initialize global variables
increase_size = False
last_file_size = None

def adjust_command(individual, increase_size, last_file_size, max_acceptable_size):
    if increase_size:
        individual['quality'] = min(individual['quality'] + 2, QUALITY_RANGE[1])
        individual['unsharp'] = f"{max(float(individual['unsharp'].split('x')[0]) + 0.1, 0):.2f}x{individual['unsharp'].split('x')[1]}"
        individual['adaptive-sharpen'] = f"{max(float(individual['adaptive-sharpen'].split('x')[0]) + 0.1, 0):.1f}x{individual['adaptive-sharpen'].split('x')[1]}"
        max_size = min(last_file_size * 1.1, max_acceptable_size)
    else:
        individual['quality'] = max(individual['quality'] - 2, QUALITY_RANGE[0])
        individual['unsharp'] = f"{min(float(individual['unsharp'].split('x')[0]) - 0.1, 10):.2f}x{individual['unsharp'].split('x')[1]}"
        individual['adaptive-sharpen'] = f"{min(float(individual['adaptive-sharpen'].split('x')[0]) - 0.1, 10):.1f}x{individual['adaptive-sharpen'].split('x')[1]}"
        max_size = max(last_file_size * 0.9, 1)  # Ensure it does not go below 1 byte
    return max_size

def timeout_handler(signum, frame):
    raise TimeoutException("Function call timed out")

def adjust_quality(individual, increase_size):
    if increase_size:
        individual['quality'] = min(individual['quality'] + 1, QUALITY_RANGE[1])
    else:
        individual['quality'] = max(individual['quality'] - 1, QUALITY_RANGE[0])

def get_smallest_image_size(directory):
    if not os.path.exists(directory):
        return None

    min_size = float('inf')
    for file in os.listdir(directory):
        file_path = os.path.join(directory, file)
        if os.path.isfile(file_path):
            file_size = os.path.getsize(file_path)
            if file_size < min_size:
                min_size = file_size
    return min_size if min_size != float('inf') else None

def cleanup_temp_files(output_directory):
    try:
        for file in os.listdir(output_directory):
            file_path = os.path.join(output_directory, file)
            if os.path.isfile(file_path):
                os.unlink(file_path)
        print()
        logging.info(f"Cleaned up temporary files in {output_directory}")
        print()
    except Exception as e:
        logging.error(f"Error cleaning up temporary files: {str(e)}")

def process_command(command, input_file, output_file, output_directory, log_file, target_size):
    try:
        logging.info(f"Processing: {os.path.basename(output_file)}")

        success = run_imagemagick_command(input_file, os.path.join(output_directory, output_file), command)
        if not success:
            logging.error(f"Failed to execute command for {os.path.basename(output_file)}")
            return False, None, False

        # Strict check for file size
        actual_size = os.path.getsize(os.path.join(output_directory, output_file))
        if actual_size > target_size * 1024:
            logging.error(f"File size ({actual_size / 1024:.2f} KB) exceeds target size ({target_size:.2f} KB)")
            return False, None, False

        result = analyze_image(input_file, os.path.join(output_directory, output_file))
        if result is not None:
            file_size, dimensions, psnr_value, ssim_value = result

            try:
                noise_level = measure_noise(os.path.join(output_directory, output_file))
            except Exception as e:
                logging.error(f"Error measuring noise for {os.path.basename(output_file)}: {str(e)}")
                noise_level = 1.0

            logging.info(f"Image: {os.path.basename(output_file)}")
            logging.info(f"Size: {file_size / 1024:.1f} KB")
            logging.info(f"PSNR: {psnr_value:.2f}, SSIM: {ssim_value:.4f}")
            logging.info(f"Noise: {noise_level:.4f}")

            quality_acceptable = (psnr_value >= PSNR_THRESHOLD and 
                                  ssim_value >= SSIM_THRESHOLD and 
                                  noise_level <= MAX_NOISE_LEVEL)
            size_acceptable = file_size <= target_size * 1024

            if size_acceptable and quality_acceptable:
                quality_status = 'Acceptable'
            elif not size_acceptable:
                quality_status = 'Rejected (Exceeds target size)'
            else:
                quality_status = 'Not Acceptable'

            logging.info(f"Quality: {quality_status}")
            print()

            with open(log_file, "a", newline="") as file:
                writer = csv.writer(file)
                writer.writerow([command, file_size, dimensions[0], dimensions[1], psnr_value, ssim_value, noise_level])

            add_command(command)

            return size_acceptable and quality_acceptable, file_size, quality_acceptable
        else:
            logging.error(f"Failed to analyze image: {os.path.basename(output_file)}")
            return False, None, False
    except Exception as e:
        print()
        logging.error(f"Error processing {os.path.basename(output_file)}: {str(e)}")
        return False, None, False

def save_best_command(best_command):
    try:
        with open(BEST_COMMANDS_FILE, "a", newline="") as file:
            writer = csv.writer(file)
            writer.writerow([datetime.now().strftime("%Y-%m-%d %H:%M:%S"), best_command])
        logging.info(f"Best command added to {BEST_COMMANDS_FILE}")
    except Exception as e:
        logging.error(f"Error saving best command to {BEST_COMMANDS_FILE}: {str(e)}")

def get_sampling_factor(input_file):
    try:
        identify_command = f"identify -format '%[jpeg:sampling-factor]' {input_file}"
        sampling_factor = subprocess.check_output(identify_command, shell=True).decode('utf-8').strip()
        if sampling_factor not in ["4:2:0", "4:2:2", "4:4:4"]:
            sampling_factor = "4:2:0"  # Default to 4:2:0 if the factor is not recognized
        return sampling_factor
    except subprocess.CalledProcessError as e:
        logging.error(f"Error getting sampling factor: {e.stderr}")
        return "4:2:0"  # Default to 4:2:0 in case of error

def get_image_file():
    script_directory = os.path.dirname(os.path.abspath(__file__))
    image_files = [file for file in os.listdir(script_directory) if file.lower().endswith((".jpg", ".jpeg", ".png"))]

    if len(image_files) == 1:
        return os.path.join(script_directory, image_files[0])
    elif len(image_files) > 1:
        logging.info("Multiple image files found in the script's directory:")
        for i, file in enumerate(image_files, start=1):
            logging.info(f"{i}. {file}")
        while True:
            try:
                choice = int(input("Please enter the number of the image file to use: "))
                if 1 <= choice <= len(image_files):
                    return os.path.join(script_directory, image_files[choice - 1])
                else:
                    logging.error("Invalid choice. Please try again.")
            except ValueError:
                logging.error("Invalid input. Please enter a valid number.")
    else:
        logging.error("No image files found in the script's directory.")
        logging.error("Please make sure there is at least one image file (JPG, JPEG, or PNG) in the same directory as the script.")
        sys.exit(1)

def detect_noise(image_path):
    image = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if image is None:
        return 0  # Return 0 if the image couldn't be read
    
    # Compute the Laplacian of the image
    laplacian = cv2.Laplacian(image, cv2.CV_64F)
    
    # Compute the variance of the Laplacian
    noise_level = laplacian.var()
    
    # Normalize the noise level to a 0-1 range
    # You may need to adjust this normalization based on your specific use case
    normalized_noise = min(noise_level / 500, 1.0)
    
    return normalized_noise

def generate_imagemagick_commands(input_file, count, target_size):
    commands = []
    sampling_factor = get_sampling_factor(input_file)
    for _ in range(count):
        quality = random.randint(QUALITY_RANGE[0], QUALITY_RANGE[1])
        unsharp = f"{np.random.uniform(0, 1):.2f}x{np.random.uniform(0, 1):.2f}+{np.random.uniform(0, 5):.1f}+{np.random.uniform(0, 0.05):.3f}"
        adaptive_sharpen = f"{np.random.uniform(0, 2):.1f}x{np.random.uniform(0, 0.5):.1f}"
        posterize = np.random.randint(64, 256)
        command = f"-strip -define jpeg:dct-method=float -interlace Plane -colorspace sRGB -filter Lanczos -define filter:blur=0.9891028367558475 -define filter:window=Jinc -define filter:lobes=3 -sampling-factor {sampling_factor} -quality {quality} -unsharp {unsharp} -adaptive-sharpen {adaptive_sharpen} -posterize {posterize} -define jpeg:extent={target_size}b"
        commands.append(command)
    return commands

def select_best_commands(log_file, num_commands, target_size):
    with open(log_file, "r") as file:
        reader = csv.DictReader(file)
        rows = list(reader)

    if not rows:
        logging.error("No valid data in the log file. Cannot select best commands.")
        return []

    valid_rows = []
    for row in rows:
        row['file_size'] = int(row['file_size'])
        row['psnr'] = float(row['psnr'])
        row['ssim'] = float(row['ssim'])
        if row['file_size'] <= target_size and row['psnr'] >= PSNR_THRESHOLD and row['ssim'] >= SSIM_THRESHOLD:
            valid_rows.append(row)

    if not valid_rows:
        logging.error("No commands produced results meeting all criteria.")
        return []

    # Sort by a combination of PSNR and SSIM, with preference for smaller file sizes
    valid_rows.sort(key=lambda r: (r['psnr'], r['ssim'], -r['file_size']), reverse=True)
    best_commands = valid_rows[:num_commands]
    return [cmd['command'] for cmd in best_commands]

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

    return generate_imagemagick_commands(input_file, output_directory, initial_population)

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

def check_and_kill_existing_processes(script_name):
    current_pid = os.getpid()
    current_script = os.path.abspath(script_name)
    killed_processes = []

    for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'status']):
        try:
            if proc.info['pid'] != current_pid and proc.info['name'] in ['python', 'python3']:
                cmdline = proc.cmdline()
                if len(cmdline) > 1 and os.path.basename(cmdline[1]) == script_name:
                    logging.info(f"Found existing process: PID {proc.info['pid']}, Status: {proc.info['status']}")
                    
                    # Try to terminate the process and all its children
                    parent = psutil.Process(proc.info['pid'])
                    for child in parent.children(recursive=True):
                        child.terminate()
                    parent.terminate()

                    gone, still_alive = psutil.wait_procs([parent], timeout=3)
                    for p in still_alive:
                        p.kill()
                    
                    killed_processes.append(proc.info['pid'])

        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
        except Exception as e:
            logging.error(f"Error handling process: {str(e)}")

    if killed_processes:
        logging.info(f"Cleaned up {len(killed_processes)} existing processes: {', '.join(map(str, killed_processes))}")
    else:
        logging.info("No existing processes found to clean up.")

    print()
    time.sleep(2)  # Wait to ensure all processes are terminated

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

def get_stored_commands():
    if os.path.exists(BEST_COMMANDS_FILE):
        with open(BEST_COMMANDS_FILE, "r") as file:
            reader = csv.reader(file)
            return [row[1] for row in reader if len(row) > 1]  # Ensure all rows with more than 1 element are read
    return []

def get_target_size(input_file, optimal_directory):
    smallest_size = get_smallest_image_size(optimal_directory)
    input_size = os.path.getsize(input_file)

    if smallest_size is not None:
        # Use the smaller of the two: smallest optimal image or 90% of input size
        target_size = min(smallest_size, input_size * 0.9)
    else:
        # If no optimal images exist, use 90% of input size
        target_size = input_size * 0.9

    # Apply a 5% safety margin
    return int(target_size * 0.95)

def adapt_stored_commands(commands, target_size):
    adapted_commands = []
    for cmd in commands:
        parts = cmd.split()
        size_constraint_added = False
        for i, part in enumerate(parts):
            if part == "-quality":
                current_quality = int(parts[i+1])
                new_quality = max(current_quality - 10, 40)  # Reduce quality, but not below 40
                parts[i+1] = str(new_quality)
            elif part == "-define" and parts[i+1].startswith("jpeg:extent="):
                parts[i+1] = f"jpeg:extent={int(target_size)}kb"
                size_constraint_added = True
        if not size_constraint_added:
            parts.append(f"-define jpeg:extent={int(target_size)}kb")
        adapted_commands.append(" ".join(parts))
    return adapted_commands

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
    logging.info(f"MUTATION_RATE: {MUTATION_RATE}\n")

    logging.info("Quality Thresholds:")
    logging.info(f"MAX_NOISE_LEVEL: {MAX_NOISE_LEVEL}")
    logging.info(f"PSNR_THRESHOLD: {PSNR_THRESHOLD}")
    logging.info(f"SSIM_THRESHOLD: {SSIM_THRESHOLD}\n")

def process_commands(input_file, commands, output_directory, log_file, target_size):
    successful_commands = []

    def process_single_command(command, i):
        output_file = f"{output_directory}/output_{i:02d}.{OUTPUT_FORMAT}"
        success = run_imagemagick_command(input_file, output_file, command)
        if success:
            result = analyze_image(input_file, output_file)
            if result is not None:
                return (command, i, result)
        return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_command = {executor.submit(process_single_command, command, i): (command, i) for i, command in enumerate(commands)}
        for future in concurrent.futures.as_completed(future_to_command):
            result = future.result()
            if result is not None:
                command, i, (file_size, dimensions, psnr_value, ssim_value, noise_level) = result
                
                with open(log_file, "a", newline="") as file:
                    writer = csv.writer(file)
                    writer.writerow([command, file_size, dimensions[0], dimensions[1], psnr_value, ssim_value, noise_level])
                
                if file_size <= target_size and psnr_value >= PSNR_THRESHOLD and ssim_value >= SSIM_THRESHOLD and noise_level <= MAX_NOISE_LEVEL:
                    successful_commands.append((command, psnr_value, ssim_value, file_size, noise_level))
                
                logging.info(f"Image: output_{i:02d}.{OUTPUT_FORMAT}")
                logging.info(f"Size: {file_size / 1024:.1f} KB")
                logging.info(f"PSNR: {psnr_value:.2f}, SSIM: {ssim_value:.4f}")
                logging.info(f"Noise: {noise_level:.4f}")
                logging.info(f"Quality: {'Acceptable' if file_size <= target_size and psnr_value >= PSNR_THRESHOLD and ssim_value >= SSIM_THRESHOLD and noise_level <= MAX_NOISE_LEVEL else 'Not Acceptable'}")
                print()

    return successful_commands

def main():
    try:
        check_and_kill_existing_processes('magick.py')
        initialize_database()
        input_file = get_image_file()
        set_magick_limits(input_file)
        output_directory = "temp-files"
        log_file = "optimization_log.csv"
        optimal_directory = "optimal-images"

        target_size = get_target_size(input_file, optimal_directory)
        logging.info(f"Adjusted target size with safety margin: {target_size / 1024:.2f} KB")

        logging.info(f"Number of CPUs detected: {NUM_CPUS}")
        logging.info(f"Using {MAX_WORKERS} worker threads for parallel processing.")

        print_configuration()

        stored_commands = get_stored_commands()
        use_stored = False
        if stored_commands:
            logging.info(f"Found {len(stored_commands)} stored commands in {BEST_COMMANDS_FILE}.")
            print()
            use_stored = input("Do you want to use these commands? (y/n): ").lower() == 'y'
            if use_stored:
                commands = adapt_stored_commands(stored_commands, target_size)
                logging.info("Using adapted stored commands for optimization.")
            else:
                commands = generate_imagemagick_commands(input_file, INITIAL_COMMAND_COUNT, target_size)
                print()
                logging.info("Generating new commands for optimization.")
        else:
            logging.info(f"No stored commands found in {BEST_COMMANDS_FILE}. Generating new commands.")
            commands = generate_imagemagick_commands(input_file, INITIAL_COMMAND_COUNT, target_size)

        os.makedirs(output_directory, exist_ok=True)
        os.makedirs(optimal_directory, exist_ok=True)

        start_time = datetime.now()

        with open(log_file, "w", newline="") as file:
            writer = csv.writer(file)
            writer.writerow(["command", "file_size", "width", "height", "psnr", "ssim", "noise"])

        all_successful_commands = []

        for generation in range(GENERATIONS):
            logging.info(f"\nGeneration {generation + 1} of {GENERATIONS}")

            # Clean up temporary files from previous generation
            cleanup_temp_files(output_directory)

            logging.info(f"Processing {len(commands)} commands:")
            print()
            successful_commands = process_commands(input_file, commands, output_directory, log_file, target_size)

            if successful_commands:
                all_successful_commands.extend(successful_commands)
                # Generate new commands based on the successful ones
                commands = generate_new_generation(successful_commands, INITIAL_COMMAND_COUNT, target_size)
            else:
                logging.info("No successful commands in this generation. Generating new commands.")
                commands = generate_imagemagick_commands(input_file, INITIAL_COMMAND_COUNT, target_size)

        if not all_successful_commands:
            logging.error("Failed to find any successful commands after all generations.")
            cleanup_temp_files(output_directory)
            return

        logging.info("\nAll generations complete.\n")

        best_command = max(all_successful_commands, key=lambda x: (x[1], x[2], -x[3]))
        logging.info(f"\nOptimization complete. Total time: {datetime.now() - start_time}\n")
        logging.info(f"Best command: {best_command[0]}")
        logging.info(f"PSNR: {best_command[1]:.2f}")
        logging.info(f"SSIM: {best_command[2]:.4f}")
        logging.info(f"File size: {best_command[3] / 1024:.2f} KB\n")

        save_best_command(best_command[0])

        optimal_output = os.path.join(optimal_directory, f"optimal_{datetime.now().strftime('%Y%m%d_%H%M%S')}.{OUTPUT_FORMAT}")
        try:
            success = run_imagemagick_command(input_file, optimal_output, best_command[0])
            if success:
                logging.info(f"Optimal command executed. Result saved as {optimal_output}")
            else:
                logging.error("Failed to execute the optimal command.")
        except Exception as e:
            logging.error(f"Error executing optimal command: {str(e)}")

        create_optimization_report(best_command[0], log_file, target_size)

    except Exception as e:
        logging.error(f"An unexpected error occurred: {str(e)}")
    finally:
        cleanup_temp_files(output_directory)
        # Ensure all child processes are terminated
        current_process = psutil.Process()
        children = current_process.children(recursive=True)
        for child in children:
            try:
                child.terminate()
            except psutil.NoSuchProcess:
                pass
        gone, still_alive = psutil.wait_procs(children, timeout=3)
        for p in still_alive:
            p.kill()

if __name__ == "__main__":
    main()
