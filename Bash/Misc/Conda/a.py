#!/usr/bin/env python3
"""
Client External Script
----------------------
This script runs on the external LLM machine (3080 Ti) on port 5001.
It loads the DeepSeek-R1-Distill-Qwen-14B-GGUF model via llama-cpp-python,
receives generation requests, and returns model completions.
It also saves conversation history in Redis for temporal memory.
Usage:
    python client_external.py --model_path /path/to/DeepSeek-R1-Distill-Qwen-14B-GGUF.bin
Additional arguments allow configuration of Redis, GPU layers, and the server port.
"""

import argparse
import logging
import json
import redis
from flask import Flask, request, jsonify

# Import llama-cpp-python (make sure it is installed)
try:
    from llama_cpp import Llama
except ImportError:
    raise ImportError("Please install llama-cpp-python (pip install llama-cpp-python)")

# Set up logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

app = Flask(__name__)

redis_client = None
model = None

def load_model(model_path, n_gpu_layers):
    """
    Loads the model using llama-cpp-python.
    """
    try:
        logging.info(f"Loading model from {model_path} with n_gpu_layers={n_gpu_layers} ...")
        return Llama(model_path=model_path, n_gpu_layers=n_gpu_layers)
    except Exception as e:
        logging.error("Error loading model: " + str(e))
        exit(1)

@app.route('/generate', methods=['POST'])
def generate():
    """
    Expects a JSON payload with at least the key "message" (the prompt).
    Uses the loaded model to generate a completion using streaming and returns the result.
    """
    try:
        data = request.get_json()
        if not data or "message" not in data:
            return jsonify({"error": "No message provided in JSON payload"}), 400

        prompt = data.get('message')
        logging.info(f"Received prompt: {prompt}")

        # Generate completion using the updated llama-cpp-python call with streaming
        response_stream = model.create_completion(
            prompt,
            max_tokens=None,
            temperature=0.6,
            top_p=0.95,
            top_k=40,
            repeat_penalty=1.2,
            stream=True,
            echo=False,
            stop=["<｜User｜>", "<｜Assistant｜>"]
        )
        generated_text = ""
        for token in response_stream:
            generated_text += token.get("text", "")

        logging.info("Generation successful.")

        # Save the interaction to Redis memory
        conversation_entry = {
            "sender": "external",
            "message": prompt,
            "response": generated_text
        }
        redis_client.rpush("conversation", json.dumps(conversation_entry))
        logging.info("Saved conversation entry to Redis.")

        return jsonify({"response": generated_text})
    except Exception as e:
        logging.exception("Error in /generate endpoint")
        return jsonify({"error": str(e)}), 500

def main():
    parser = argparse.ArgumentParser(
        description="Client External for LLM (DeepSeek-R1-Distill-Qwen-14B-GGUF on 3080 Ti)"
    )
    parser.add_argument('--model_path', type=str, required=True,
                        help="Path to the model file (DeepSeek-R1-Distill-Qwen-14B-GGUF).")
    parser.add_argument('--redis_host', type=str, default='localhost',
                        help="Hostname for the Redis server (default: localhost).")
    parser.add_argument('--redis_port', type=int, default=6379,
                        help="Port for the Redis server (default: 6379).")
    parser.add_argument('--port', type=int, default=5001,
                        help="Port for this client to run on (default: 5001).")
    parser.add_argument('--gpu_layers', type=int, default=-1,
                        help="Number of GPU layers to use (default: -1 for all).")
    args = parser.parse_args()

    global redis_client, model
    try:
        redis_client = redis.Redis(host=args.redis_host, port=args.redis_port, db=0)
        redis_client.ping()
        logging.info("Connected to Redis successfully.")
    except Exception as e:
        logging.error("Failed to connect to Redis: " + str(e))
        exit(1)

    model = load_model(args.model_path, args.gpu_layers)
    logging.info(f"Starting Client External on port {args.port} ...")
    app.run(host='0.0.0.0', port=args.port)

if __name__ == '__main__':
    main()
