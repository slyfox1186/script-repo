#!/usr/bin/env python3

# Purpose: Uses Machine Learning to generate an optimal command line whose focus is to produce the highest quality image and the smallest file size.

import argparse
import concurrent.futures
import configparser
import csv
import hashlib
import logging
import multiprocessing
import numpy as np
import os
import psutil
import random
import signal
import subprocess
import sys
import tkinter as tk
from datetime import datetime
from PIL import Image, ExifTags
from skimage.metrics import peak_signal_noise_ratio as psnr
from skimage.metrics import structural_similarity as ssim
from tkinter import filedialog, messagebox, BooleanVar, Checkbutton
from tkinter import messagebox
from tqdm import tqdm

# General parameters
BEST_COMMANDS_FILE = "best_commands.csv"
MAX_WORKERS = min(2, multiprocessing.cpu_count())
OUTPUT_FORMAT = "jpg"
USE_STORED_COMMANDS = False

# Command line parameters
INITIAL_COMMAND_COUNT = 10
REFINEMENT_FACTOR = 2
QUALITY_RANGE = (82, 91)
MIN_OPTIONS_PER_COMMAND = 3

# Genetic Algorithm parameters
POPULATION_SIZE = 10
GENERATIONS = 1
MUTATION_RATE = 0.2

# Quality threshold
PSNR_THRESHOLD = 35
SSIM_THRESHOLD = 0.94

class CustomFormatter(logging.Formatter):
    grey = "\x1b[38;21m"
    yellow = "\x1b[33;21m"
    red = "\x1b[31;21m"
    bold_red = "\x1b[31;1m"
    reset = "\x1b[0m"
    format = "%(message)s"

    FORMATS = {
        logging.INFO: grey + format + reset,
        logging.WARNING: yellow + format + reset,
        logging.ERROR: red + format + reset,
        logging.CRITICAL: bold_red + format + reset
    }

    def format(self, record):
        log_fmt = self.FORMATS.get(record.levelno)
        formatter = logging.Formatter(log_fmt)
        return formatter.format(record)

# Create a custom logger
logger = logging.getLogger("ImageOptimizer")
logger.setLevel(logging.INFO)

# Create a custom stream handler with colors
stream_handler = logging.StreamHandler()
stream_handler.setLevel(logging.INFO)
stream_handler.setFormatter(CustomFormatter())

# Add the custom stream handler to the logger
logger.addHandler(stream_handler)

def check_profiles(config_path):
    config = configparser.ConfigParser(interpolation=None)
    config.read(config_path)

    if 'Profiles' not in config:
        logger.error("No 'Profiles' section found in the config file.")
        sys.exit("Error: No 'Profiles' section found in the config file. Please define at least one profile.")

    profiles = config['Profiles']
    active_profiles = [key for key, value in profiles.items() if value.strip()]

    if len(active_profiles) > 1:
        logger.error("Multiple profiles are activated in the config file: " + ", ".join(active_profiles))
        sys.exit("Error: Multiple profiles are activated in the config file. Please ensure only one profile is enabled.")

    if len(active_profiles) == 0:
        logger.error("No profiles are activated in the config file.")
        sys.exit("Error: No profiles are activated in the config file. Please enable one profile.")

def parse_arguments():
    parser = argparse.ArgumentParser(description="Image Optimization Script")
    parser.add_argument("-i", "--input", nargs="+", help="Input image file(s) or directory(ies)", required=True)
    parser.add_argument("-o", "--output", help="Output directory", default="optimized")
    parser.add_argument("-c", "--config", help="Configuration file", default="config.ini")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    parser.add_argument("--gui", action="store_true", help="Launch GUI interface")
    return parser.parse_args()

def load_config(config_file):
    config = configparser.ConfigParser()
    config.read(config_file)

    global INITIAL_COMMAND_COUNT, MAX_WORKERS, QUALITY_RANGE, MIN_OPTIONS_PER_COMMAND
    global REFINEMENT_FACTOR, OUTPUT_FORMAT, BEST_COMMANDS_FILE, POPULATION_SIZE
    global GENERATIONS, MUTATION_RATE, PSNR_THRESHOLD, SSIM_THRESHOLD
    global USE_STORED_COMMANDS

    # General settings
    INITIAL_COMMAND_COUNT = config.getint('General', 'initial_command_count', fallback=INITIAL_COMMAND_COUNT)
    MAX_WORKERS = config.getint('General', 'max_workers', fallback=MAX_WORKERS)
    MIN_OPTIONS_PER_COMMAND = config.getint('General', 'min_options_per_command', fallback=MIN_OPTIONS_PER_COMMAND)
    OUTPUT_FORMAT = config.get('General', 'output_format', fallback=OUTPUT_FORMAT)
    POPULATION_SIZE = config.getint('General', 'population_size', fallback=POPULATION_SIZE)
    GENERATIONS = config.getint('General', 'generations', fallback=GENERATIONS)
    MUTATION_RATE = config.getfloat('General', 'mutation_rate', fallback=MUTATION_RATE)

    # Quality settings
    quality_range = config.get('Quality', 'quality_range', fallback='82,91')
    QUALITY_RANGE = tuple(map(int, quality_range.split(',')))
    PSNR_THRESHOLD = config.getfloat('Quality', 'psnr_threshold', fallback=PSNR_THRESHOLD)
    SSIM_THRESHOLD = config.getfloat('Quality', 'ssim_threshold', fallback=SSIM_THRESHOLD)

    # Files
    BEST_COMMANDS_FILE = config.get('Files', 'best_commands_file', fallback=BEST_COMMANDS_FILE)
    USE_STORED_COMMANDS = config.getboolean('Files', 'use_stored_commands', fallback=False)

    # Optimization
    REFINEMENT_FACTOR = config.getint('Optimization', 'refinement_factor', fallback=REFINEMENT_FACTOR)

    return config

def get_image_fingerprint(image_path):
    with open(image_path, "rb") as f:
        file_hash = hashlib.md5()
        chunk = f.read(8192)
        while chunk:
            file_hash.update(chunk)
            chunk = f.read(8192)
    return file_hash.hexdigest()

def get_stored_commands():
    if os.path.exists(BEST_COMMANDS_FILE):
        with open(BEST_COMMANDS_FILE, "r") as file:
            reader = csv.reader(file)
            commands = [row[1] for row in reader if len(row) > 1]
        if len(commands) >= 2:
            return commands
    return []

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

        os.environ.update(magick_limits)
        logger.info("ImageMagick Limits:")
        for key, value in magick_limits.items():
            logger.info(f"  - {key}: {value}")
    except Exception as e:
        logger.error(f"Error setting ImageMagick limits: {str(e)}")
        default_limits = {
            'MAGICK_AREA_LIMIT': '128MB',
            'MAGICK_DISK_LIMIT': '1GB',
            'MAGICK_MEMORY_LIMIT': '256MB',
            'MAGICK_WIDTH_LIMIT': '16KP',
            'MAGICK_HEIGHT_LIMIT': '16KP',
            'MAGICK_THREAD_LIMIT': str(MAX_WORKERS),
        }
        os.environ.update(default_limits)
        logger.info("Default ImageMagick Limits:")
        for key, value in default_limits.items():
            logger.info(f"  - {key}: {value}")

def run_imagemagick_command(input_file, output_file, command):
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    full_command = f"magick {input_file} {command} {output_file}"
    try:
        result = subprocess.run(full_command, shell=True, check=True, stderr=subprocess.PIPE, text=True, timeout=300)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Error executing: {os.path.basename(output_file)}")
        logger.error(f"Error message: {e.stderr}")
        return False
    except subprocess.TimeoutExpired:
        logger.error(f"Timeout executing: {os.path.basename(output_file)}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error executing command: {str(e)}")
        return False

def analyze_image(input_file, output_file):
    try:
        with Image.open(input_file) as original_image, Image.open(output_file) as compressed_image:
            original_size = os.path.getsize(input_file)
            compressed_size = os.path.getsize(output_file)

            if original_image.size != compressed_image.size:
                original_image = original_image.resize(compressed_image.size, Image.LANCZOS)

            chunk_size = 1024
            total_psnr = 0
            total_ssim = 0
            num_chunks = 0

            for i in range(0, original_image.height, chunk_size):
                for j in range(0, original_image.width, chunk_size):
                    box = (j, i, min(j+chunk_size, original_image.width), min(i+chunk_size, original_image.height))
                    original_chunk = np.array(original_image.crop(box))
                    compressed_chunk = np.array(compressed_image.crop(box))

                    total_psnr += psnr(original_chunk, compressed_chunk)
                    total_ssim += ssim(original_chunk, compressed_chunk, channel_axis=-1)
                    num_chunks += 1

        psnr_value = total_psnr / num_chunks
        ssim_value = total_ssim / num_chunks

        return compressed_size, compressed_image.size, psnr_value, ssim_value
    except Exception as e:
        logger.error(f"Error analyzing image: {output_file}")
        logger.error(f"Error message: {str(e)}")
        return None

def create_individual():
    return {
        "unsharp": f"{np.random.uniform(0, 1):.2f}x{np.random.uniform(0, 1):.2f}+{np.random.uniform(0, 5):.1f}+{np.random.uniform(0, 0.05):.3f}",
        "adaptive-sharpen": f"{np.random.uniform(0, 2):.1f}x{np.random.uniform(0, 0.5):.1f}",
        "quality": np.random.randint(82, 91),
    }

def mutate(individual):
    if np.random.random() < MUTATION_RATE:
        key = random.choice(list(individual.keys()))
        if key == "quality":
            individual[key] = np.random.randint(82, 91)
        else:
            values = [float(x) for x in individual[key].split('x')[1].split('+')]
            mutated_values = [max(0, min(v + np.random.normal(0, 0.1), 10)) for v in values]
            individual[key] = f"0x{'+'.join([f'{v:.2f}' for v in mutated_values])}"
    return individual

def crossover(parent1, parent2):
    child = {}
    for key in parent1.keys():
        if np.random.random() < 0.5:
            child[key] = parent1[key]
        else:
            child[key] = parent2[key]
    return child

def fitness(input_file, output_file, output_directory):
    try:
        result = analyze_image(input_file, os.path.join(output_directory, output_file))
        if result is not None:
            file_size, _, psnr_value, ssim_value = result
            original_size = os.path.getsize(input_file)
            size_reduction = (original_size - file_size) / original_size

            if psnr_value < PSNR_THRESHOLD or ssim_value < SSIM_THRESHOLD:
                return -float('inf'), file_size, False

            fitness_score = (0.3 * psnr_value) + (0.5 * ssim_value) + (0.2 * size_reduction)
            return fitness_score, file_size, True
        else:
            return -float('inf'), float('inf'), False
    except Exception as e:
        logger.error(f"Error in fitness evaluation: {str(e)}")
        return -float('inf'), float('inf'), False

def adjust_command(individual, increase_size, last_file_size, max_acceptable_size):
    if increase_size:
        individual['quality'] = min(individual['quality'] + 2, QUALITY_RANGE[1])
        individual['unsharp'] = f"{max(float(individual['unsharp'].split('x')[0]) - 0.1, 0):.2f}x{individual['unsharp'].split('x')[1]}"
        individual['adaptive-sharpen'] = f"{max(float(individual['adaptive-sharpen'].split('x')[0]) - 0.1, 0):.1f}x{individual['adaptive-sharpen'].split('x')[1]}"
        max_size = min(last_file_size * 1.1, max_acceptable_size)
    else:
        individual['quality'] = max(individual['quality'] - 2, QUALITY_RANGE[0])
        individual['unsharp'] = f"{min(float(individual['unsharp'].split('x')[0]) + 0.1, 10):.2f}x{individual['unsharp'].split('x')[1]}"
        individual['adaptive-sharpen'] = f"{min(float(individual['adaptive-sharpen'].split('x')[0]) + 0.1, 10):.1f}x{individual['adaptive-sharpen'].split('x')[1]}"
        max_size = last_file_size * 0.9

    return max_size

def generate_imagemagick_commands(input_file, output_directory, initial_population=None, max_size_limit=None, config=None):
    used_commands = set(get_stored_commands())

    sampling_factor = get_sampling_factor(input_file)
    log_file = "optimization_log.csv"
    max_generations_without_improvement = config.getint('Optimization', 'max_generations_without_improvement', fallback=10)
    generations_without_improvement = 0
    best_fitness_score = -float('inf')
    best_command = None

    base_options = config.get('Advanced', 'base_options', fallback="").split(',')
    base_options = [option.strip() for option in base_options if option.strip()]

    if initial_population:
        population = initial_population
    else:
        population = [create_individual() for _ in range(POPULATION_SIZE)]

    last_quality_acceptable = True
    increase_size = False
    last_file_size = os.path.getsize(input_file)
    max_acceptable_size = min(last_file_size, max_size_limit) if max_size_limit else last_file_size

    for generation in range(GENERATIONS):
        logger.info(f"Generation Round: {generation + 1}/{GENERATIONS}")
        logger.info("")
        fitness_scores = []
        generation_best_score = -float('inf')

        for i, individual in enumerate(population):
            selected_options = random.sample(base_options, k=random.randint(MIN_OPTIONS_PER_COMMAND, len(base_options)))
            base_command = " ".join(selected_options)

            max_size = min(adjust_command(individual, increase_size, last_file_size, max_acceptable_size), max_size_limit) if max_size_limit else adjust_command(individual, increase_size, last_file_size, max_acceptable_size)
            command = f"{base_command} -define jpeg:extent={int(max_size)}b -quality {individual['quality']} -unsharp {individual['unsharp']} -adaptive-sharpen {individual['adaptive-sharpen']}"

            if command in used_commands:
                continue

            used_commands.add(command)
            valid_command = validate_command(command)
            if not valid_command:
                logger.error(f"Generated invalid command: {command}")
                continue

            output_file = f"temp_output_{generation:02d}_{i:02d}.jpg"
            success, file_size, quality_acceptable = process_command(command, input_file, output_file, output_directory, log_file)
            if success:
                fitness_score, file_size, quality_acceptable = fitness(input_file, output_file, output_directory)
                fitness_scores.append((individual, fitness_score, quality_acceptable))

                if fitness_score > generation_best_score:
                    generation_best_score = fitness_score

                if fitness_score > best_fitness_score:
                    best_fitness_score = fitness_score
                    best_command = command
                    logger.info(f"New best fitness score: {best_fitness_score}")
                    logger.info("")

                if quality_acceptable:
                    if not last_quality_acceptable:
                        logger.info("Quality is acceptable again. Starting to reduce image size for following outputs.")
                        logger.info("")
                    last_quality_acceptable = True
                    increase_size = False
                    max_acceptable_size = max(max_acceptable_size, file_size)
                else:
                    if last_quality_acceptable:
                        logger.info("Quality is not acceptable. Increasing image size for following outputs.")
                        logger.info("")
                    last_quality_acceptable = False
                    increase_size = True

                last_file_size = file_size

        if generation_best_score > best_fitness_score:
            best_fitness_score = generation_best_score
            generations_without_improvement = 0
        else:
            generations_without_improvement += 1

        if generations_without_improvement >= max_generations_without_improvement:
            logger.info(f"No improvement for {max_generations_without_improvement} generations. Stopping optimization.")
            break

        fitness_scores.sort(key=lambda x: x[1], reverse=True)
        population = [individual for individual, _, _ in fitness_scores[:POPULATION_SIZE // 2]]

        while len(population) < POPULATION_SIZE:
            parent1, parent2 = random.sample(population, 2)
            child = crossover(parent1, parent2)
            child = mutate(child)
            max_size = min(adjust_command(child, increase_size, last_file_size, max_acceptable_size), max_size_limit) if max_size_limit else adjust_command(child, increase_size, last_file_size, max_acceptable_size)
            child_command = f"{base_command} -define jpeg:extent={int(max_size)}b -quality {child['quality']} -unsharp {child['unsharp']} -adaptive-sharpen {child['adaptive-sharpen']}"
            population.append(child)

    if best_command:
        best_individual = next((ind for ind in population if " ".join(random.sample(base_options, random.randint(MIN_OPTIONS_PER_COMMAND, len(base_options)))) + \
            f" -define jpeg:extent={int(max_acceptable_size)}b -quality {ind['quality']} -unsharp {ind['unsharp']} -adaptive-sharpen {ind['adaptive-sharpen']}" == best_command), None)
        if best_individual is None:
            best_individual = create_individual()
    else:
        best_individual = max(population, key=lambda x: fitness(
            input_file,
            "temp_best.jpg",
            output_directory,
        )[0])

    best_command = " ".join(random.sample(base_options, random.randint(MIN_OPTIONS_PER_COMMAND, len(base_options)))) + \
        f" -define jpeg:extent={int(max_acceptable_size)}b -quality {best_individual['quality']} -unsharp {best_individual['unsharp']} -adaptive-sharpen {best_individual['adaptive-sharpen']}"

    temp_best_file = "temp_best.jpg"
    success, _, _ = process_command(best_command, input_file, temp_best_file, output_directory, log_file)
    if success:
        logger.info(f"Best command: {best_command}")
        logger.info("")
    else:
        logger.error("Failed to execute the best command during final evaluation.")

    return [best_command]

def process_command(command, input_file, output_file, output_directory, log_file):
    try:
        logger.info(f"==========================================")
        logger.info(f"Processing: {os.path.basename(output_file)}")
        logger.info(f"==========================================")
        logger.info("")

        success = run_imagemagick_command(input_file, os.path.join(output_directory, output_file), command)
        if not success:
            logger.error("Failed to execute command.")
            return False, None, False

        result = analyze_image(input_file, os.path.join(output_directory, output_file))
        if result is not None:
            file_size, dimensions, psnr_value, ssim_value = result
            with open(log_file, "a", newline="") as file:
                writer = csv.writer(file)
                writer.writerow([command, file_size, dimensions[0], dimensions[1], psnr_value, ssim_value])

            logger.info(f"Command: {command}")
            logger.info("")
            logger.info(f"File Size: {file_size/1024:.1f}KB")
            logger.info(f"Dimensions: {dimensions[0]}x{dimensions[1]}")
            logger.info("")

            quality_acceptable = psnr_value >= PSNR_THRESHOLD and ssim_value >= SSIM_THRESHOLD
            logger.info(f"Quality: {'Acceptable' if quality_acceptable else 'Not Acceptable'}")
            logger.info("")
            logger.info("Metrics:")
            logger.info(f" - Size: {file_size/1024:.1f}KB")
            logger.info(f" - PSNR: {psnr_value:.2f}")
            logger.info(f" - SSIM: {ssim_value:.4f}")
            logger.info("")

            action = "Decreasing" if quality_acceptable else "Increasing"
            logger.info(f"Action: Next image size will be {action.lower()}.")
            logger.info("")
            return True, file_size, quality_acceptable
        else:
            logger.error("Failed to analyze image.")
            return False, None, False
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return False, None, False

def cleanup_temp_files(output_directory):
    try:
        for file in os.listdir(output_directory):
            file_path = os.path.join(output_directory, file)
            if os.path.isfile(file_path):
                os.unlink(file_path)
        logger.info(f"Cleaned up temporary files in {output_directory}")
    except Exception as e:
        logger.error(f"Error cleaning up temporary files: {str(e)}")

def save_best_command(best_command):
    with open(BEST_COMMANDS_FILE, "a", newline="") as file:
        writer = csv.writer(file)
        writer.writerow([datetime.now().strftime("%Y-%m-%d %H:%M:%S"), best_command])

def get_sampling_factor(input_file):
    try:
        identify_command = f"identify -format '%[jpeg:sampling-factor]' {input_file}"
        sampling_factor = subprocess.check_output(identify_command, shell=True).decode('utf-8').strip()
        if sampling_factor not in ["4:2:0", "4:2:2", "4:4:4"]:
            sampling_factor = "4:2:0"
        return sampling_factor
    except subprocess.CalledProcessError as e:
        logger.error(f"Error getting sampling factor: {e.stderr}")
        return "4:2:0"

def get_image_files(input_paths):
    image_files = []
    for input_path in input_paths:
        if os.path.isfile(input_path):
            image_files.append(input_path)
        elif os.path.isdir(input_path):
            image_files.extend([os.path.join(input_path, f) for f in os.listdir(input_path) if f.lower().endswith(('.jpg', '.jpeg', '.png'))])
        else:
            logger.error(f"Invalid input path: {input_path}")
    return image_files

def select_best_commands(log_file, num_commands):
    with open(log_file, "r") as file:
        reader = csv.DictReader(file)
        rows = list(reader)

    if not rows:
        logger.error("No valid data in the log file. Cannot select best commands.")
        return []

    for row in rows:
        row['file_size'] = int(row['file_size'])
        row['psnr'] = float(row['psnr'])
        row['ssim'] = float(row['ssim'])

    rows.sort(key=lambda r: (r['psnr'], r['ssim'], -r['file_size']), reverse=True)
    best_commands = rows[:num_commands]
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

    os.chmod("full-commands.sh", 0o755)

def check_and_kill_existing_processes(script_name):
    current_pid = os.getpid()
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if proc.info['pid'] != current_pid and proc.info['cmdline'] and script_name in proc.info['cmdline']:
                logger.info(f"Terminated existing process: {proc.info['pid']} {proc.info['name']}")
                proc.terminate()
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
    os.system('clear' if os.name == 'posix' else 'cls')

def validate_command(command):
    command_parts = command.split()
    i = 0
    while i < len(command_parts):
        if command_parts[i] in ["-strip"]:
            i += 1
            continue
        elif command_parts[i] in ["-filter", "-define", "-dither", "-posterize", "-interlace", "-colorspace", "-sampling-factor", "-quality", "-unsharp", "-adaptive-sharpen"]:
            if i + 1 >= len(command_parts) or command_parts[i + 1].startswith('-'):
                logger.error(f"Missing argument for {command_parts[i]}")
                return False
            i += 2
        else:
            logger.error(f"Invalid command part: {command_parts[i]}")
            return False
    return True

def compare_images(original, optimized):
    original_size = os.path.getsize(original)
    optimized_size = os.path.getsize(optimized)
    size_reduction = (original_size - optimized_size) / original_size * 100

    with Image.open(original) as img1, Image.open(optimized) as img2:
        psnr_value = psnr(np.array(img1), np.array(img2))
        ssim_value = ssim(np.array(img1), np.array(img2), channel_axis=-1)

    logger.info(f"Image Comparison: {os.path.basename(original)} vs {os.path.basename(optimized)}")
    logger.info(f"Size reduction: {size_reduction:.2f}%")
    logger.info(f"PSNR: {psnr_value:.2f}")
    logger.info(f"SSIM: {ssim_value:.4f}")

def create_gui(config):
    root = tk.Tk()
    root.title("Image Optimization")

    input_paths = tk.StringVar()
    output_path = tk.StringVar()
    use_stored_commands = BooleanVar()

    tk.Label(root, text="Input Image/Directory:").grid(row=0, column=0, sticky="e")
    tk.Entry(root, textvariable=input_paths, width=50).grid(row=0, column=1)
    tk.Button(root, text="Browse", command=lambda: input_paths.set(filedialog.askopenfilenames() if config.getboolean('General','batch_mode', fallback=False) else filedialog.askopenfilename())).grid(row=0, column=2)

    tk.Label(root, text="Output Directory:").grid(row=1, column=0, sticky="e")
    tk.Entry(root, textvariable=output_path, width=50).grid(row=1, column=1)
    tk.Button(root, text="Browse", command=lambda: output_path.set(filedialog.askdirectory())).grid(row=1, column=2)

    Checkbutton(root, text="Use stored commands in the CSV file", variable=use_stored_commands).grid(row=2, column=1, sticky="w")

    tk.Button(root, text="Optimize", command=lambda: optimize_images_gui(input_paths.get(), output_path.get(), use_stored_commands.get(), config, root)).grid(row=3, column=1)

    root.mainloop()

def optimize_images_gui(input_paths, output_path, use_stored_commands, config, root):
    args = argparse.Namespace(input=input_paths, output=output_path, config="config.ini", verbose=False)
    
    image_files = get_image_files(args.input)
    for input_file in image_files:
        process_single_image_gui(input_file, args, config, use_stored_commands)

    messagebox.showinfo("Optimization Complete", "Image optimization process has finished.")
    root.quit()

def optimize_images(input_paths, output_path, config):
    args = argparse.Namespace(input=input_paths, output=output_path, config="config.ini", verbose=False)
    image_files = get_image_files(args.input)
    for input_file in image_files:
        process_single_image(input_file, args, config)

def main(args):
    if args.config:
        check_profiles(args.config)
        logging.getLogger().setLevel(logging.DEBUG)

    config = load_config(args.config)
    
    enable_gui = config.getboolean('GUI', 'enable_gui', fallback=False)

    if args.gui or enable_gui:
        create_gui(config)
    else:
        check_and_kill_existing_processes('magick.py')
        
        optimize_images(args.input, args.output, config)

def check_profiles(config_path):
    config = configparser.ConfigParser(interpolation=None)
    config.read(config_path)

    if 'Profiles' not in config:
        logger.error("No 'Profiles' section found in the config file.")
        sys.exit("Error: No 'Profiles' section found in the config file. Please define at least one profile.")

    profiles = config['Profiles']
    active_profiles = [key for key, value in profiles.items() if value.strip()]

    if len(active_profiles) > 1:
        logger.error("Multiple profiles are activated in the config file: " + ", ".join(active_profiles))
        sys.exit("Error: Multiple profiles are activated in the config file. Please ensure only one profile is enabled.")

    if len(active_profiles) == 0:
        logger.error("No profiles are activated in the config file.")
        sys.exit("Error: No profiles are activated in the config file. Please enable one profile.")

def process_single_image_gui(input_file, args, config, use_stored_commands):
    logger.info(f"Processing image: {input_file}")
    image_fingerprint = get_image_fingerprint(input_file)
    set_magick_limits(input_file)
    
    output_directory = os.path.join(args.output, "temp")
    optimal_directory = os.path.join(args.output, "optimal")
    log_file = os.path.join(args.output, "optimization_log.csv")

    os.makedirs(output_directory, exist_ok=True)
    os.makedirs(optimal_directory, exist_ok=True)

    optimal_file, max_size_limit = get_smallest_optimal_image_size()

    stored_commands = get_stored_commands()
    if stored_commands and use_stored_commands:
        logger.info(f'Using {len(stored_commands)} stored commands from "{BEST_COMMANDS_FILE}"')
        commands = stored_commands
    else:
        logger.info("Generating new commands for optimization.")
        commands = generate_imagemagick_commands(input_file, output_directory, max_size_limit=max_size_limit, config=config)

def process_single_image(input_file, args, config):
    logger.info(f"Date: {datetime.now().strftime('%m-%d-%Y')}")
    logger.info(f"Time: {datetime.now().strftime('%I:%M:%S %p')}")
    logger.info("")
    logger.info(f"Input File: {input_file}")
    logger.info("")
    set_magick_limits(input_file)
    
    output_directory = os.path.join(args.output, "temp")
    optimal_directory = os.path.join(args.output, "optimal")
    log_file = os.path.join(args.output, "optimization_log.csv")

    os.makedirs(output_directory, exist_ok=True)
    os.makedirs(optimal_directory, exist_ok=True)

    optimal_file, max_size_limit = get_smallest_optimal_image_size()

    stored_commands = get_stored_commands()
    if stored_commands:
        logger.info(f"Found [{len(stored_commands)}] stored commands in the file: {BEST_COMMANDS_FILE}")
        logger.info("")
        use_stored = input("Do you want to use these commands? (y/n): ").lower() == 'y'
        logger.info("")
        if use_stored:
            commands = stored_commands
            logger.info("Using stored commands for optimization.")
        else:
            commands = generate_imagemagick_commands(input_file, output_directory, max_size_limit=max_size_limit, config=config)
            logger.info("Generating new commands for optimization.")
    else:
        logger.info(f"No stored commands found in \"{BEST_COMMANDS_FILE}\". Generating new commands.")
        commands = generate_imagemagick_commands(input_file, output_directory, max_size_limit=max_size_limit, config=config)

    start_time = datetime.now()

    with open(log_file, "w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["command", "file_size", "width", "height", "psnr", "ssim"])

    num_commands = len(commands)
    with tqdm(total=num_commands, desc="Optimizing", unit="command") as pbar:
        with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            futures = [executor.submit(process_command, command, input_file, f"output_{i:02}.{OUTPUT_FORMAT}", output_directory, log_file)
                       for i, command in enumerate(commands)]
            for future in concurrent.futures.as_completed(futures):
                future.result()
                pbar.update(1)

    logger.info("Command processing complete.")

    best_commands = select_best_commands(log_file, 1)
    if best_commands:
        best_command = best_commands[0]
        logger.info(f"Optimization complete. Total time: {datetime.now() - start_time}")
        logger.info(f"Best command: {best_command}")

        if not use_stored:
            save_best_command(best_command)
            logger.info(f"Best command added to {BEST_COMMANDS_FILE}")

        optimal_output = os.path.join(optimal_directory, f"optimal_{datetime.now().strftime('%Y%m%d_%H%M%S')}.{OUTPUT_FORMAT}")
        try:
            success = run_imagemagick_command(input_file, optimal_output, best_command)
            if success:
                logger.info(f"Output File: {optimal_output}")
                new_size = os.path.getsize(optimal_output)
                if max_size_limit and new_size < max_size_limit:
                    logger.info(f"New optimal image is smaller than previous best ({new_size/1024:.1f}KB vs {max_size_limit/1024:.1f}KB)")
                elif max_size_limit:
                    logger.info(f"New optimal image is not smaller than previous best ({new_size/1024:.1f}KB vs {max_size_limit/1024:.1f}KB)")
            else:
                logger.error("Failed to execute the optimal command.")
        except Exception as e:
            logger.error(f"Error executing optimal command: {str(e)}")

        compare_images(input_file, optimal_output)

        generate_optimization_report(best_command, log_file, args.output)
    else:
        logger.error("No valid commands found. Unable to determine the best command.")

    cleanup_temp_files(output_directory)

def generate_optimization_report(best_command, log_file, output_directory):
    report_file = os.path.join(output_directory, "optimization_report.html")

    with open(report_file, "w") as file:
        file.write("<html><head><title>Optimization Report</title></head><body>")
        file.write(f"<h1>Optimization Report</h1>")
        file.write(f"<h2>Optimal ImageMagick Command</h2>")
        file.write(f"<pre>{best_command}</pre>")
        file.write("<p>This command was selected as the best based on the following criteria:</p>")
        file.write("<ul>")
        file.write("<li>Highest PSNR value, indicating minimal loss of image quality.</li>")
        file.write("<li>Highest SSIM value, indicating preservation of structural similarity.</li>")
        file.write("<li>Smallest file size, achieving the best compression.</li>")
        file.write("</ul>")
        file.write("<p>The optimization process prioritized image quality (PSNR and SSIM) while minimizing file size.</p>")
        file.write("<h2>Runner-up Commands</h2>")
        file.write("<ul>")
        runner_up_commands = select_best_commands(log_file, 5)[1:]
        for command in runner_up_commands:
            file.write(f"<li>{command}</li>")
        file.write("</ul>")
        file.write("<p>These commands also performed well but were slightly inferior in terms of PSNR, SSIM, or file size compared to the optimal command.</p>")
        file.write("</body></html>")

    logger.info(f"Optimization report generated: {report_file}")

def get_smallest_optimal_image_size():
    optimal_directory = "optimal-images"

    if not os.path.exists(optimal_directory):
        return None, None

    smallest_size = float('inf')
    smallest_file = None

    for file in os.listdir(optimal_directory):
        if file.startswith('optimal_') and file.lower().endswith(('.jpg', '.jpeg', '.png')):
            file_path = os.path.join(optimal_directory, file)
            file_size = os.path.getsize(file_path)
            if file_size < smallest_size:
                smallest_size = file_size
                smallest_file = file

    if smallest_file:
        logger.info(f"Output Name: {smallest_file}")
        logger.info("")
        logger.info(f"Maximum Size Considered: {smallest_size/1024:.1f}KB")
        return smallest_file, smallest_size
    else:
        logger.info("No optimal images found.")
        return None, None

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

        os.environ.update(magick_limits)
        logger.info("ImageMagick Limits:")
        for key, value in magick_limits.items():
            logger.info(f"  - {key}: {value}")
        logger.info("")
    except Exception as e:
        logger.error(f"Error setting ImageMagick limits: {str(e)}")
        default_limits = {
            'MAGICK_AREA_LIMIT': '128MB',
            'MAGICK_DISK_LIMIT': '1GB',
            'MAGICK_MEMORY_LIMIT': '256MB',
            'MAGICK_WIDTH_LIMIT': '16KP',
            'MAGICK_HEIGHT_LIMIT': '16KP',
            'MAGICK_THREAD_LIMIT': str(MAX_WORKERS),
        }
        os.environ.update(default_limits)
        logger.info("Default ImageMagick Limits:")
        for key, value in default_limits.items():
            logger.info(f"  - {key}: {value}")
        logger.info("")

def get_smallest_optimal_image_size():
    optimal_directory = "optimal-images"

    if not os.path.exists(optimal_directory):
        return None, None

    smallest_size = float('inf')
    smallest_file = None

    for file in os.listdir(optimal_directory):
        if file.startswith('optimal_') and file.lower().endswith(('.jpg', '.jpeg', '.png')):
            file_path = os.path.join(optimal_directory, file)
            file_size = os.path.getsize(file_path)
            if file_size < smallest_size:
                smallest_size = file_size
                smallest_file = file

    if smallest_file:
        logger.info(f"Max Output Size Limit: {smallest_size/1024:.1f}KB")
        return smallest_file, smallest_size
    else:
        logger.info("No optimal images found.")
        return None, None

def get_smallest_optimal_image_size():
    optimal_directory = "optimal-images"

    if not os.path.exists(optimal_directory):
        return None, None

    smallest_size = float('inf')
    smallest_file = None

    for file in os.listdir(optimal_directory):
        if file.startswith('optimal_') and file.lower().endswith(('.jpg', '.jpeg', '.png')):
            file_path = os.path.join(optimal_directory, file)
            file_size = os.path.getsize(file_path)
            if file_size < smallest_size:
                smallest_size = file_size
                smallest_file = file

    if smallest_file:
        logger.info(f"Optimal Output Name: {smallest_file}")
        logger.info("")
        logger.info(f"Maximum Size Considered: {smallest_size/1024:.1f}KB")
        logger.info("")
        return smallest_file, smallest_size
    else:
        logger.info("No optimal images found.")
        return None, None

def preserve_metadata(source_image, destination_image):
    try:
        with Image.open(source_image) as img:
            exif = img.info['exif']

        with Image.open(destination_image) as img:
            img.save(destination_image, exif=exif)

        logger.info(f"Metadata preserved for {destination_image}")
    except Exception as e:
        logger.error(f"Error preserving metadata: {str(e)}")

def smart_crop(image_path, output_path, target_ratio=1.0):
    try:
        with Image.open(image_path) as img:
            width, height = img.size
            current_ratio = width / height

            if current_ratio > target_ratio:
                new_width = int(height * target_ratio)
                left = (width - new_width) // 2
                img_cropped = img.crop((left, 0, left + new_width, height))
            else:
                new_height = int(width / target_ratio)
                top = (height - new_height) // 2
                img_cropped = img.crop((0, top, width, top + new_height))

            img_cropped.save(output_path)
        logger.info(f"Smart cropped image saved as {output_path}")
    except Exception as e:
        logger.error(f"Error during smart cropping: {str(e)}")

def resize_image(image_path, output_path, new_size):
    try:
        with Image.open(image_path) as img:
            img_resized = img.resize(new_size, Image.LANCZOS)
            img_resized.save(output_path)
        logger.info(f"Resized image saved as {output_path}")
    except Exception as e:
        logger.error(f"Error during image resizing: {str(e)}")

def save_optimization_profile(profile_name, command):
    profiles_file = "optimization_profiles.json"
    profiles = {}
    if os.path.exists(profiles_file):
        with open(profiles_file, "r") as f:
            profiles = json.load(f)

    profiles[profile_name] = command

    with open(profiles_file, "w") as f:
        json.dump(profiles, f, indent=2)

    logger.info(f"Optimization profile '{profile_name}' saved.")

def load_optimization_profile(profile_name):
    profiles_file = "optimization_profiles.json"
    if os.path.exists(profiles_file):
        with open(profiles_file, "r") as f:
            profiles = json.load(f)
        if profile_name in profiles:
            return profiles[profile_name]

    logger.error(f"Optimization profile '{profile_name}' not found.")
    return None

if __name__ == "__main__":
    args = parse_arguments()
    main(args)
