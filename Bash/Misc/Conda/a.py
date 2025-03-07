#!/usr/bin/env python3
"""
debate_client.py

./debate_client.py --host 0.0.0.0 --port 5000 --debug False

This script starts a minimal Flask server that exposes an endpoint to process debate prompts.
When contacted by the Debate Server, it uses the local LLM (via llama-cpp-python) to generate a counter-argument.

Usage:
    ./debate_client.py [--host 0.0.0.0] [--port 5000] [--debug False]
                        [--model-path ./models/name.gguf] [--n_gpu_layers 20]

Example:
    ./debate_client.py --host 0.0.0.0 --port 5000 --debug False
"""
import argparse
import logging
import os
from flask import Flask, request, jsonify
import sys

# Attempt to import the llama-cpp-python module
try:
    from llama_cpp import Llama
except ImportError as e:
    logging.error("Failed to import llama_cpp: %s", e)
    sys.exit(1)

# Configure logging
logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s: %(message)s')

# Parse command-line arguments with a detailed help menu
parser = argparse.ArgumentParser(
    description="Debate Client for processing debate messages via a local LLM (GeForce 3080TI)."
)
parser.add_argument("--host", type=str, default="0.0.0.0",
                    help="Host to run the client Flask server on (default: 0.0.0.0)")
parser.add_argument("--port", type=int, default=5000,
                    help="Port to run the client Flask server on (default: 5000)")
parser.add_argument("--debug", type=bool, default=False,
                    help="Run Flask in debug mode (default: False)")
parser.add_argument("--model-path", type=str, default="./models/name.gguf",
                    help="Path to the local LLM model for the client (default: ./models/name.gguf)")
parser.add_argument("--n_gpu_layers", type=int, default=-1,
                    help="Number of GPU layers to use (default: -1 for the client)")
args = parser.parse_args()

# Initialize the local client LLM model using llama-cpp-python
try:
    client_llm = Llama(
        model_path=args.model_path,
        n_batch=512,
        n_threads=os.cpu_count(),
        main_gpu=0,
        n_gpu_layers=args.n_gpu_layers,
        flash_attn=True,
        use_mlock=True,
        use_mmap=True,
        offload_kqv=True,
        verbose=True
    )
    logging.info("Client LLM model loaded successfully from '%s'", args.model_path)
except Exception as e:
    logging.error("Failed to load client LLM model: %s", e)
    sys.exit(1)

# Create the Flask app
app = Flask(__name__)
app.config["DEBUG"] = args.debug

@app.route("/process_debate", methods=["POST"])
def process_debate():
    """
    Process a debate request.
    Expected JSON payload:
        - topic: The debate topic.
        - previous: The previous argument from the server.
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON payload provided"}), 400

    topic = data.get("topic", "").strip()
    previous = data.get("previous", "")
    if not topic:
        return jsonify({"error": "No topic provided in payload"}), 400

    try:
        # Formulate a prompt for the client LLM model
        prompt = (f"Debate on: {topic}\n"
                  f"Previous argument: {previous}\n"
                  "Counter-argument from Client (3080TI):")
        response_obj = client_llm(prompt, max_tokens=200)
        client_response = response_obj["choices"][0]["text"].strip()
    except Exception as e:
        logging.error("Client LLM generation error: %s", e)
        return jsonify({"error": f"Client LLM error: {str(e)}"}), 500

    return jsonify({"response": client_response})

def main():
    """Start the client Flask server."""
    try:
        logging.info("Starting Debate Client on %s:%s", args.host, args.port)
        app.run(host=args.host, port=args.port, debug=args.debug)
    except Exception as e:
        logging.error("Error running Flask client server: %s", e)

if __name__ == "__main__":
    main()
