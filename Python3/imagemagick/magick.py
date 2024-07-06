#!/usr/bin/env python3

# Purpose: Uses Machine Learning to general an optimal command line whose focus is to produce the highest quality image and the smallest file size.

import concurrent.futures
import csv
import logging
import multiprocessing
import numpy as np
import os
import random
import psutil
import signal
import subprocess
import sys
from datetime import datetime
from PIL import Image
from skimage.metrics import peak_signal_noise_ratio as psnr
from skimage.metrics import structural_similarity as ssim

# User-configurable variables
INITIAL_COMMAND_COUNT = 20
MAX_WORKERS = min(2, multiprocessing.cpu_count())
QUALITY_RANGE = (82, 91)
MIN_OPTIONS_PER_COMMAND = 3
REFINEMENT_FACTOR = 2
OUTPUT_FORMAT = "jpg"
BEST_COMMANDS_FILE = "best_commands.csv"

# Genetic Algorithm parameters
POPULATION_SIZE = 20
GENERATIONS = 4
MUTATION_RATE = 0.2

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s', datefmt='this %m-%d-%Y %I-%M-%S %p')

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
        logging.info(f"Set ImageMagick limits: {magick_limits}")
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
        logging.info(f"Set default ImageMagick limits: {default_limits}")

def run_imagemagick_command(input_file, output_file, command):
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    full_command = f"magick {input_file} {command} {output_file}"
    try:
        result = subprocess.run(full_command, shell=True, check=True, stderr=subprocess.PIPE, text=True, timeout=300)
        logging.info(f"Executed: {os.path.basename(output_file)}")
        return True
    except subprocess.CalledProcessError as e:
        logging.error(f"Error executing: {os.path.basename(output_file)}")
        logging.error(f"Error message: {e.stderr}")
        return False
    except subprocess.TimeoutExpired:
        logging.error(f"Timeout executing: {os.path.basename(output_file)}")
        return False
    except Exception as e:
        logging.error(f"Unexpected error executing command: {str(e)}")
        return False

def analyze_image(input_file, output_file):
    try:
        with Image.open(input_file) as original_image, Image.open(output_file) as compressed_image:
            original_size = os.path.getsize(input_file)
            compressed_size = os.path.getsize(output_file)

            # Resize the original image to match the compressed image dimensions
            if original_image.size != compressed_image.size:
                original_image = original_image.resize(compressed_image.size, Image.LANCZOS)

            # Calculate PSNR and SSIM in smaller chunks
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
        logging.error(f"Error analyzing image: {output_file}")
        logging.error(f"Error message: {str(e)}")
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

def fitness(command, input_file, output_file, output_directory):
    try:
        run_imagemagick_command(input_file, os.path.join(output_directory, output_file), command)
        result = analyze_image(input_file, os.path.join(output_directory, output_file))
        if result is not None:
            file_size, _, psnr_value, ssim_value = result
            original_size = os.path.getsize(input_file)
            size_reduction = (original_size - file_size) / original_size

            if psnr_value < 35 or ssim_value < 0.90:  # Increase threshold for noise penalty
                return -float('inf'), file_size

            # Balanced fitness score with more emphasis on SSIM
            fitness_score = (0.3 * psnr_value) + (0.5 * ssim_value) + (0.2 * size_reduction)
            return fitness_score, file_size
        else:
            return -float('inf'), float('inf')
    except Exception as e:
        logging.error(f"Error in fitness evaluation: {str(e)}")
        return -float('inf'), float('inf')

def generate_imagemagick_commands(input_file, output_directory, initial_population=None):
    sampling_factor = get_sampling_factor(input_file)

    base_options = [
        ("-filter", ["Triangle", "Lanczos", "Mitchell", "Gaussian"]),
        ("-define", ["filter:support=2"]),
        ("-strip", [""]),
        ("-dither", ["None"]),
        ("-posterize", ["136"]),
        ("-define", ["jpeg:fancy-upsampling=off", "jpeg:dct-method=float", "jpeg:dct-method=fast"]),
        ("-interlace", ["none", "Plane"]),
        ("-colorspace", ["sRGB"]),
        ("-sampling-factor", [sampling_factor]),
    ]

    if initial_population:
        population = initial_population
    else:
        population = [create_individual() for _ in range(POPULATION_SIZE)]

    for generation in range(GENERATIONS):
        logging.info(f"Generation: {generation + 1}/{GENERATIONS}")
        fitness_scores = []
        for i, individual in enumerate(population):
            selected_options = random.sample(base_options, k=random.randint(MIN_OPTIONS_PER_COMMAND, len(base_options)))
            base_command = " ".join([f"{option[0]} {random.choice(option[1])}" for option in selected_options if option[1]])

            # Validate the command before execution
            if not validate_command(base_command):
                logging.error(f"Generated invalid command: {base_command}")
                continue

            # Add individual-specific options
            command = f"{base_command} -quality {individual['quality']} -unsharp {individual['unsharp']} -adaptive-sharpen {individual['adaptive-sharpen']}"

            output_file = f"temp_output_{generation:02d}_{i:02d}.jpg"
            fitness_score, file_size = fitness(command, input_file, output_file, output_directory)
            logging.info(f"Generated command: {command}")
            fitness_scores.append((individual, fitness_score, file_size))

        fitness_scores.sort(key=lambda x: x[1], reverse=True)
        population = [individual for individual, _, _ in fitness_scores[:POPULATION_SIZE // 2]]

        while len(population) < POPULATION_SIZE:
            parent1, parent2 = random.sample(population, 2)
            child = crossover(parent1, parent2)
            child = mutate(child)
            population.append(child)

    best_individual = max(population, key=lambda x: fitness(
        " ".join([f"{option[0]} {random.choice(option[1])}" for option in random.sample(base_options, random.randint(MIN_OPTIONS_PER_COMMAND, len(base_options)))]) +
        f" -quality {x['quality']} -unsharp {x['unsharp']} -adaptive-sharpen {x['adaptive_sharpen']}",
        input_file, "temp_best.jpg", output_directory
    )[0])

    best_command = " ".join([f"{option[0]} {random.choice(option[1])}" for option in random.sample(base_options, random.randint(MIN_OPTIONS_PER_COMMAND, len(base_options)))]) + \
        f" -quality {best_individual['quality']} -unsharp {best_individual['unsharp']} -adaptive-sharpen {best_individual['adaptive_sharpen']}"

    return [best_command]

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

class TimeoutException(Exception):
    pass

def timeout_handler(signum, frame):
    raise TimeoutException("Function call timed out")

def process_command(command, input_file, output_file, output_directory):
    try:
        success = run_imagemagick_command(input_file, os.path.join(output_directory, output_file), command)
        if not success:
            return

        result = analyze_image(input_file, os.path.join(output_directory, output_file))
        if result is not None:
            file_size, dimensions, psnr_value, ssim_value = result
            with open("optimization_log.csv", "a", newline="") as file:
                writer = csv.writer(file)
                writer.writerow([command, file_size, dimensions[0], dimensions[1], psnr_value, ssim_value])
            logging.info(f"Processed: {os.path.basename(output_file)} (Size: {file_size/1024:.1f}KB, PSNR: {psnr_value:.2f}, SSIM: {ssim_value:.4f})")
    except Exception as e:
        logging.error(f"Error processing {os.path.basename(output_file)}: {str(e)}")

def cleanup_temp_files(output_directory):
    try:
        for file in os.listdir(output_directory):
            file_path = os.path.join(output_directory, file)
            if os.path.isfile(file_path):
                os.unlink(file_path)
        logging.info(f"Cleaned up temporary files in {output_directory}")
    except Exception as e:
        logging.error(f"Error cleaning up temporary files: {str(e)}")

def get_stored_commands():
    if os.path.exists(BEST_COMMANDS_FILE):
        with open(BEST_COMMANDS_FILE, "r") as file:
            reader = csv.reader(file)
            return [row[1] for row in reader if len(row) > 1]
    return []

def save_best_command(best_command):
    with open(BEST_COMMANDS_FILE, "a", newline="") as file:
        writer = csv.writer(file)
        writer.writerow([datetime.now().strftime("this %m-%d-%Y %I-%M-%S %p"), best_command])

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
        print("Multiple image files found in the script's directory:")
        for i, file in enumerate(image_files, start=1):
            print(f"{i}. {file}")
        while True:
            try:
                choice = int(input("Please enter the number of the image file to use: "))
                if 1 <= choice <= len(image_files):
                    return os.path.join(script_directory, image_files[choice - 1])
                else:
                    print("Invalid choice. Please try again.")
            except ValueError:
                print("Invalid input. Please enter a valid number.")
    else:
        print("No image files found in the script's directory.")
        print("Please make sure there is at least one image file (JPG, JPEG, or PNG) in the same directory as the script.")
        sys.exit(1)

def select_best_commands(log_file, num_commands):
    with open(log_file, "r") as file:
        reader = csv.DictReader(file)
        rows = list(reader)

    if not rows:
        logging.error("No valid data in the log file. Cannot select best commands.")
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

    os.chmod("full-commands.sh", 0o755)  # Make the script executable

def check_and_kill_existing_processes(script_name):
    current_pid = os.getpid()
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if proc.info['pid'] != current_pid and proc.info['cmdline'] and script_name in proc.info['cmdline']:
                logging.info(f"Terminated existing process: {proc.info['pid']} {proc.info['name']}")
                proc.terminate()
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
    # Clear the screen
    os.system('clear' if os.name == 'posix' else 'cls')

def main():
    check_and_kill_existing_processes('magick.py')
    input_file = get_image_file()
    set_magick_limits(input_file)
    output_directory = "output"
    optimal_directory = "optimal-images"
    log_file = "optimization_log.csv"

    stored_commands = get_stored_commands()
    use_stored = False
    if stored_commands:
        print(f"Found {len(stored_commands)} stored commands in {BEST_COMMANDS_FILE}.")
        use_stored = input("Do you want to use these commands? (y/n): ").lower() == 'y'
        if use_stored:
            commands = stored_commands
            print("Using stored commands for optimization.")
        else:
            commands = generate_imagemagick_commands(input_file, output_directory)
            print(f"Generating new commands for optimization.")
    else:
        print(f"No stored commands found in {BEST_COMMANDS_FILE}. Generating new commands.")
        commands = generate_imagemagick_commands(input_file, output_directory)

    os.makedirs(output_directory, exist_ok=True)
    os.makedirs(optimal_directory, exist_ok=True)

    start_time = datetime.now()

    with open(log_file, "w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["command", "file_size", "width", "height", "psnr", "ssim"])

    print(f"Processing {len(commands)} commands:")
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [executor.submit(process_command, command, input_file, f"output_{i:02}.{OUTPUT_FORMAT}", output_directory)
                   for i, command in enumerate(commands)]
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as e:
                logging.error(f"Error in future: {str(e)}")

    print("\nCommand processing complete.")

    best_commands = select_best_commands(log_file, 1)
    if best_commands:
        best_command = best_commands[0]
        print(f"\nOptimization complete. Total time: {datetime.now() - start_time}")
        print(f"\nBest command: {best_command}")

        if not use_stored:
            save_best_command(best_command)
            print(f"Best command added to {BEST_COMMANDS_FILE}")

        optimal_output = os.path.join(optimal_directory, f"optimal_{datetime.now().strftime('%Y%m%d_%H%M%S')}.{OUTPUT_FORMAT}")
        try:
            success = run_imagemagick_command(input_file, optimal_output, best_command)
            if success:
                print(f"Optimal command executed. Result saved as {optimal_output}")
            else:
                print("Failed to execute the optimal command.")
        except Exception as e:
            logging.error(f"Error executing optimal command: {str(e)}")

        with open("optimization_report.txt", "w") as file:
            file.write(f"Optimal ImageMagick command: {best_command}\n\n")
            file.write("This command was selected as the best based on the following criteria:\n")
            file.write("1. Highest PSNR value, indicating minimal loss of image quality.\n")
            file.write("2. Highest SSIM value, indicating preservation of structural similarity.\n")
            file.write("3. Smallest file size, achieving the best compression.\n")
            file.write("The optimization process prioritized image quality (PSNR and SSIM) while minimizing file size.\n\n")
            file.write("Runner-up commands:\n")
            runner_up_commands = select_best_commands(log_file, 5)[1:]
            for command in runner_up_commands:
                file.write(f"- {command}\n")
            file.write("\nThese commands also performed well but were slightly inferior in terms of PSNR, SSIM, or file size compared to the optimal command.")
    else:
        print("No valid commands found. Unable to determine the best command.")

    cleanup_temp_files(output_directory)

if __name__ == "__main__":
    main()
