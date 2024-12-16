# FLUX Image Generator Web Interface

A simple web interface for the FLUX.1-schnell image generation model. This application provides a user-friendly GUI to generate images using the FLUX model from Black Forest Labs.

![image](https://github.com/user-attachments/assets/5672402b-6297-4c45-98ba-669ab4295b41)

## Features

- Clean, modern web interface
- Real-time generation progress tracking
- Adjustable image settings:
  - Width and height
  - Number of inference steps (1-4)
  - Guidance scale for creativity vs accuracy (0.0-1.5)
  - Random seed control
  - Option to save generated images
- Smart aspect ratio handling:
  - Common presets (1:1, 4:3, 16:9, 2:3, 3:2)
  - Automatic dimension adjustments while maintaining ratios
  - Values automatically adjust when manually changing width/height
- Realistic Mode:
  - Enhanced prompts with realistic details
  - Optimized settings for photorealism
- Local storage for user preferences
- Improved file handling:
  - Automatic filename truncation for long prompts
  - Unique hash suffixes for similar prompts
  - Organized output directory structure

## Requirements

- Python 3.8+
- CUDA-capable GPU
- Required Python packages:
  ```
  flask
  torch
  diffusers
  pillow
  huggingface-hub
  ```

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/slyfox1186/script-repo
   cd script-repo/AI/flux-image-creator
   ```

2. Install the required packages:
   ```bash
   pip install flask torch diffusers pillow huggingface-hub
   ```

3. The first time you run the application, it will automatically download the FLUX model files.

## Usage

1. Start the server:
   ```bash
   python app.py
   ```

2. Open your web browser and go to:
   ```
   http://localhost:5000
   ```

3. In the web interface:
   - Enter your prompt in the text area
   - Adjust settings as needed:
     - Image dimensions (width/height)
     - Select an aspect ratio preset or use custom dimensions
     - Number of steps (1-4)
     - Guidance scale (0.0-1.5, lower = more creative, higher = more accurate)
     - Random seed (-1 for random, or specify a number for reproducible results)
   - Toggle "Save Generated Images" if you want to save the images locally
   - Enable "Realistic Mode" for enhanced photorealistic results
   - Click "Generate Image" to create your image

4. Generated images (if saving is enabled) will be stored in the `output` directory.

## Environment Variables

- `MODEL_ID`: The Hugging Face model ID (default: "black-forest-labs/FLUX.1-schnell")
- `HF_HUB_ENABLE_HF_TRANSFER`: Enabled by default for faster downloads

## Recent Updates

- Added intelligent aspect ratio maintenance while editing dimensions
- Implemented Realistic Mode for enhanced photorealistic outputs
- Improved filename handling for long prompts
- Changed output directory from 'output_images' to 'output'
- Added local storage for user preferences
- Enhanced error handling and logging
- Added progress tracking with Server-Sent Events

## Notes

- The FLUX model is optimized for speed and can generate images in just a few steps
- Image generation time depends on your GPU capabilities
- The progress bar shows real-time progress through the generation steps
- User preferences are saved locally and persist between sessions
- Long prompts are automatically truncated in filenames while maintaining uniqueness

## License

This project uses the FLUX model which is subject to its own license terms. Please refer to the [FLUX model card](https://huggingface.co/black-forest-labs/FLUX.1-schnell) for more information. assets/5672402b-6297-4c45-98ba-669ab4295b41)
