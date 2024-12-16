#!/usr/bin/env python3

import base64
import io
import json
import logging
import os
import re
import subprocess
import time
import torch
from diffusers import FluxPipeline
from flask import (
    Flask,
    jsonify,
    render_template,
    Response,
    request
)
from PIL import Image

# Set environment variable for Hugging Face transfer
os.environ['HF_HUB_ENABLE_HF_TRANSFER'] = '1'

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Check if model is downloaded and download if missing
MODEL_ID = os.getenv("MODEL_ID", "black-forest-labs/FLUX.1-schnell")
MODEL_CACHE_DIR = os.path.expanduser("~/.cache/huggingface/hub")
MODEL_PATH = os.path.join(MODEL_CACHE_DIR, "models--" + MODEL_ID.replace("/", "--"))

if not os.path.exists(MODEL_PATH):
    logger.info("Model not found. Downloading FLUX model...")
    try:
        subprocess.run("huggingface-cli download 'black-forest-labs/FLUX.1-schnell'", shell=True, check=True)
        logger.info("Model downloaded successfully!")
    except subprocess.CalledProcessError as e:
        logger.error(f"Error downloading model: {str(e)}")
        raise

app = Flask(__name__)

OUTPUT_DIR = "output"

# Create output directory if it doesn't exist
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Global variable to track progress
generation_progress = 0
pipe = None

def sanitize_filename(prompt):
    # Replace spaces with underscores and remove invalid filename characters
    filename = prompt.strip()
    filename = re.sub(r'[^\w\s-]', '', filename)
    filename = re.sub(r'[-\s]+', '_', filename)
    
    # Truncate the filename to a reasonable length (e.g., 100 characters)
    # Add a hash of the full prompt to ensure uniqueness
    if len(filename) > 100:
        # Get first 90 characters and add hash of full prompt
        prompt_hash = hex(hash(prompt))[-8:]  # Last 8 chars of hash
        filename = f"{filename[:90]}_{prompt_hash}"
    
    return filename + ".png"

def generate_image(prompt, width, height, steps, guidance_scale=0.0, sequence_length=256, seed=-1, save_image=True):
    try:
        global generation_progress, pipe
        generation_progress = 0
        
        # Initialize model if needed
        if pipe is None:
            logger.info("Initializing FLUX pipeline...")
            pipe = FluxPipeline.from_pretrained(
                MODEL_ID,
                torch_dtype=torch.bfloat16,
                use_fast=True
            )
            pipe.enable_sequential_cpu_offload()
            pipe.enable_attention_slicing(1)
            torch.cuda.empty_cache()
            logger.info("Pipeline initialized successfully")
        
        # Generate the image
        logger.info("Starting image generation process...")
        logger.info("=" * 50)
        logger.info("GUIDANCE SCALE VERIFICATION:")
        logger.info(f"1. Received value: {guidance_scale}")
        logger.info(f"2. Type: {type(guidance_scale)}")
        logger.info(f"3. Range check: 0.0 <= {guidance_scale} <= 1.5: {0.0 <= guidance_scale <= 1.5}")
        logger.info("=" * 50)

        with torch.inference_mode():
            def callback_fn(pipe, i, t, latents):
                global generation_progress
                generation_progress = int(((i + 1) / steps) * 100)
                logger.info(f"Step {i + 1}/{steps} - Using guidance_scale={guidance_scale}")
                return latents

            generation_params = {
                "prompt": prompt,
                "guidance_scale": float(guidance_scale),  # Ensure it's float
                "num_inference_steps": steps,
                "max_sequence_length": sequence_length,
                "height": height,
                "width": width,
                "callback_on_step_end": callback_fn,
                "callback_on_step_end_tensor_inputs": ["latents"]
            }
            
            # Log the exact parameters being sent to FLUX
            logger.info("=" * 50)
            logger.info("FLUX PARAMETERS:")
            for key, value in generation_params.items():
                if key != "callback_on_step_end" and key != "callback_on_step_end_tensor_inputs":
                    logger.info(f"{key}: {value} (type: {type(value)})")
            logger.info("=" * 50)
            
            image = pipe(**generation_params).images[0]
            logger.info("Image generation completed successfully")
        
        # Save if requested
        if save_image:
            filename = f"{sanitize_filename(prompt)}.png"
            output_path = os.path.join(OUTPUT_DIR, filename)
            image.save(output_path)
        
        # Convert to base64
        buffered = io.BytesIO()
        image.save(buffered, format="PNG")
        image_data = base64.b64encode(buffered.getvalue()).decode()
        
        return image_data
            
    except Exception as e:
        logger.error("=" * 50)
        logger.error("Error during image generation")
        logger.error("-" * 50)
        logger.error(f"Error details: {str(e)}")
        logger.error("Stack trace:", exc_info=True)
        logger.error("=" * 50)
        raise Exception(f"Error generating image: {str(e)}")

@app.route('/')
def index():
    logger.info("Serving index page")
    return render_template('index.html')

@app.route('/generate', methods=['POST'])
def generate():
    try:
        logger.info("=" * 50)
        logger.info("New generation request received")
        logger.info("=" * 50)
        
        data = request.json
        logger.info("Request data received:")
        logger.info(f"Raw request data: {json.dumps(data, indent=2)}")
        
        # Parse and validate parameters
        prompt = data.get('prompt', '')
        width = int(data.get('width', 768))
        height = int(data.get('height', 768))
        steps = min(max(int(data.get('steps', 4)), 1), 4)
        guidance_scale = min(max(0.0, float(data.get('guidance_scale', 0.8))), 1.5)
        seed = int(data.get('seed', -1))
        save_image = data.get('save_image', False)
        
        logger.info("Parsed parameters:")
        logger.info(f"  Prompt: '{prompt}'")
        logger.info(f"  Width: {width}")
        logger.info(f"  Height: {height}")
        logger.info(f"  Steps: {steps}")
        logger.info(f"  Guidance Scale: {guidance_scale}")
        logger.info(f"  Seed: {seed}")
        logger.info(f"  Save Image: {save_image}")
        logger.info("-" * 50)
        
        image_data = generate_image(
            prompt, 
            width, 
            height, 
            steps, 
            guidance_scale,
            sequence_length=256,
            seed=seed,
            save_image=save_image
        )
        
        logger.info("Sending successful response")
        return jsonify({
            'status': 'success',
            'image': image_data
        })
        
    except Exception as e:
        logger.error("=" * 50)
        logger.error("Error in generate endpoint")
        logger.error("-" * 50)
        logger.error(f"Error details: {str(e)}")
        logger.error("Stack trace:", exc_info=True)
        logger.error("=" * 50)
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/progress')
def progress():
    def generate():
        last_progress = -1
        while True:
            if generation_progress != last_progress:
                last_progress = generation_progress
                yield f"data: {json.dumps({'percent': generation_progress})}\n\n"
            time.sleep(0.1)
            if generation_progress >= 100:
                break
    return Response(generate(), mimetype='text/event-stream')

if __name__ == '__main__':
    logger.info("Starting Flask application...")
    os.environ['PYTORCH_CUDA_ALLOC_CONF'] = 'expandable_segments:True'
    app.run(port=5000, debug=True) 
