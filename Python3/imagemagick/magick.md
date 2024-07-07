# Image Optimization Script using ImageMagick and Machine Learning

You can source the script on GitHub [here](https://github.com/slyfox1186/script-repo/blob/main/Python3/imagemagick/magick.py)

## What My Project Does:
Hi, everyone! I've been working on a Python script that aims to find the most optimal ImageMagick command for compressing images while maintaining the highest possible quality. I would love to get your feedback, suggestions, and help in improving this script to make it even better.

## Target Audience:
This project is designed for developers, photographers, and anyone interested in optimizing images for web use or storage without compromising quality. It's especially useful for those who regularly work with large image files and need efficient ways to reduce file size while preserving image integrity.

## Comparison:
This script uses a unique combination of machine learning techniques and ImageMagick parameters to achieve optimal results. Unlike manual optimization, which can be time-consuming and less effective, this script automates the process and iteratively improves the output quality and compression ratio.

## Goal

The primary goal of this script is to automatically find the best ImageMagick command that produces the highest quality compressed image with the most space savings. It achieves this by using machine learning techniques, specifically a genetic algorithm and K-means clustering, to optimize the various ImageMagick parameters and find the most suitable combination.

## How It Works

Here's a detailed explanation of how the script works:

1. The script starts by setting up some user-configurable variables, such as the initial command count, maximum number of workers, quality range, and genetic algorithm parameters.

2. It defines several functions for setting ImageMagick limits, running ImageMagick commands, analyzing images, creating and mutating individuals for the genetic algorithm, and evaluating the fitness of each command.

3. The `generate_imagemagick_commands()` function is the core of the optimization process. It creates a population of random ImageMagick commands and iteratively evolves them over multiple generations using the genetic algorithm. The fitness of each command is evaluated based on the PSNR (Peak Signal-to-Noise Ratio), SSIM (Structural Similarity Index), and file size of the compressed image.

4. After the optimization process, the script selects the best command based on the highest PSNR and SSIM values while minimizing the file size.

5. The script then executes the optimal command on the input image and saves the result as "optimal_TIMESTAMP.jpg" in the current directory.

6. It also saves the best command found during the optimization process to a CSV file named "best_commands.csv". This file serves as a log to keep track of the best commands discovered over time. Each row in the CSV file contains a timestamp and the corresponding best command.

7. When running the script, it checks if a "best_commands.csv" file already exists. If it does, the script prompts the user to choose whether to use the stored commands from the file or generate new commands for optimization.

8. Finally, it generates an "optimization_report.txt" file containing details about the optimal command and runner-up commands.

## Usage

To use this script, follow these steps:

1. Make sure you have Python 3 and the required dependencies installed (numpy, PIL, skimage, sklearn).

2. Place the script file (`magick.py`) and the image file you want to optimize in the same directory.

3. Open a terminal or command prompt and navigate to the directory containing the script and image file.

4. Run the script using the following command:

   ```
   python3 magick.py
   ```

5. If there are multiple image files in the directory, the script will prompt you to select the desired image file.

6. If a "best_commands.csv" file exists, the script will ask if you want to use the stored commands or generate new commands for optimization.

7. The script will then start the optimization process, displaying the progress and results in the terminal.

8. Once the optimization is complete, you will find the optimized image file ("optimal_TIMESTAMP.jpg"), the optimization report ("optimization_report.txt"), and the updated "best_commands.csv" file in the same directory.

## Example Commands

```bash
python3 magick.py -i input.jpg -o output_directory
```

### Using a specific config file

```bash
python3 magick.py -i input.jpg -o output_directory -c custom_config.ini
```

### Enabling verbose output

```bash
python3 magick.py -i input.jpg -o output_directory -v
```

### Launch GUI mode

```bash
python3 magick.py --gui
```

### Process a directory of images

```bash
python3 magick.py -i input_directory -o output_directory
```

### Combine options

```bash
python3 magick.py -i input_directory -o output_directory -c custom_config.ini -v
```

### Use default output directory

```bash
python3 magick.py -i input.jpg
```

### Process a single image with verbose output and GUI

```bash
python3 magick.py -i input.jpg -v --gui
```

### Process images with a custom config and verbose output

```bash
python3 magick.py -i input_directory -o output_directory -c production_config.ini -v
```

### Use the script in a shell pipeline

```bash
find . -name "*.jpg" | xargs -I {} python3 magick.py -i {} -o optimized_images
```

### Run with increased logging level (if supported by your logging configuration)

```bash
PYTHONVERBOSE=2 python3 magick.py -i input.jpg -o output_directory
```

### Run with a specific Python interpreter

```bash
/usr/local/bin/python3.9 magick.py -i input.jpg -o output_directory
```

### Run with environment variables

```bash
MAX_WORKERS=16 python3 magick.py -i input_directory -o output_directory
```

### Run with debugging enabled (if you've implemented debug mode)

```bash
python3 -m pdb magick.py -i input.jpg -o output_directory
```

### Run with profiling

```bash
python3 -m cProfile -o profile_output.pstats magick.py -i input_directory -o output_directory
```

### Run with memory profiling (requires memory_profiler package)

```bash
python3 -m memory_profiler magick.py -i input.jpg -o output_directory
```

### Run with a specific optimization profile (if implemented)

```bash
python3 magick.py -i input.jpg -o output_directory --profile web_optimization
```

### Run in batch mode with a list of files

```bash
python3 magick.py -i file_list.txt -o output_directory --batch
```

### Run with nice command for lower priority

```bash
nice -n 19 python3 magick.py -i input_directory -o output_directory
```
