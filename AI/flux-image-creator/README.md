# FLUX Image Generator Web Interface

A simple web interface for the FLUX.1-schnell image generation model. This application provides a user-friendly GUI to generate images using the FLUX model from Black Forest Labs.

## Features

- Clean, modern web interface
- Real-time generation progress tracking
- Adjustable image settings:
  - Width and height
  - Number of inference steps (1-4)
  - Guidance scale for creativity vs accuracy
  - Random seed control
  - Option to save generated images
- Common aspect ratio presets
- Local image saving toggle

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
   git clone [repository-url]
   cd [repository-name]
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
     - Number of steps (1-4)
     - Guidance scale (lower = more accurate, higher = more creative)
     - Random seed (-1 for random, or specify a number for reproducible results)
   - Toggle "Save Generated Images" if you want to save the images locally
   - Click "Generate Image" to create your image

4. Generated images (if saving is enabled) will be stored in the `output_images` directory.

## Environment Variables

- `MODEL_ID`: The Hugging Face model ID (default: "black-forest-labs/FLUX.1-schnell")
- `HF_HUB_ENABLE_HF_TRANSFER`: Enabled by default for faster downloads

## Notes

- The FLUX model is optimized for speed and can generate images in just a few steps
- Image generation time depends on your GPU capabilities
- The progress bar shows real-time progress through the generation steps
- The interface automatically maintains aspect ratios when using presets

## License

This project uses the FLUX model which is subject to its own license terms. Please refer to the [FLUX model card](https://huggingface.co/black-forest-labs/FLUX.1-schnell) for more information. 
