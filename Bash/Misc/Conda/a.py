#!/usr/bin/env python3
"""
LLM Server for GeForce 3080 Ti using DeepSeek-R1-Distill-Qwen-14B (Streaming Enabled)
========================================================================================

This server exposes a /chat API endpoint for generating responses using the 
DeepSeek-R1-Distill-Qwen-14B model (GGUF format) via llama-cpp-python. It supports streaming 
mode when the request payload includes "stream": true, yielding tokens one by one.

Usage:
    python3 llm_server_3080.py --model_path ./models/model_3090.gguf [--host 0.0.0.0]
                               [--port 5001] [--gpu_layers -1] [--max_tokens 256]
                               [--temperature 0.7] [--n_threads 8]

Arguments:
    --model_path    Path to the DeepSeek-R1-Distill-Qwen-14B model file (default: ./models/model_3090.gguf)
    --host          Host IP to bind (default: 0.0.0.0)
    --port          Port number (default: 5001)
    --gpu_layers    Number of GPU layers (default: -1)
    --max_tokens    Maximum tokens to generate (default: 256)
    --temperature   Temperature for generation (default: 0.7)
    --n_threads     Number of CPU threads to use (default: 8)
"""

import argparse
import sys
import os
from flask import Flask, request, jsonify, Response
from llama_cpp import Llama

app = Flask(__name__)

def create_llm(model_path, gpu_layers, n_threads, **kwargs):
    try:
        # Initialize the model using best practices.
        return Llama(model_path=model_path, n_gpu_layers=gpu_layers, n_threads=n_threads, verbose=False, **kwargs)
    except Exception as e:
        print(f"Error initializing LLM: {e}", file=sys.stderr)
        sys.exit(1)

def parse_args():
    parser = argparse.ArgumentParser(description="LLM Server for GeForce 3080 Ti using DeepSeek-R1-Distill-Qwen-14B")
    parser.add_argument("--model_path", default="./models/model_3090.gguf",
                        help="Path to the DeepSeek-R1-Distill-Qwen-14B model file (default: ./models/model_3090.gguf)")
    parser.add_argument("--host", default="0.0.0.0", help="Host IP to bind (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=5001, help="Port number (default: 5001)")
    parser.add_argument("--gpu_layers", type=int, default=-1, help="Number of GPU layers (default: -1)")
    parser.add_argument("--max_tokens", type=int, default=4096, help="Maximum tokens to generate (default: 256)")
    parser.add_argument("--temperature", type=float, default=0.6, help="Temperature for generation (default: 0.7)")
    parser.add_argument("--n_threads", type=int, default=os.cpu_count(), help="Number of CPU threads to use (default: 8)")
    return parser.parse_args()

args = parse_args()
llm = create_llm(args.model_path, args.gpu_layers, args.n_threads)

@app.route("/chat", methods=["POST"])
def chat():
    try:
        data = request.get_json()
        if not data or "message" not in data:
            return jsonify({"error": "No message provided"}), 400
        message = data["message"]
        stream_flag = data.get("stream", True)
        if stream_flag:
            def generate():
                # Use streaming mode to yield tokens one by one.
                for token_data in llm(
                    message,
                    max_tokens=4096,
                    temperature=0.6,
                    stream=True,
                    echo=False,
                    top_p=0.95,
                    top_k=40,
                    stop=["<｜User｜>", "<｜Assistant｜>"]
                ):
                    token_text = token_data.get("token", "")
                    yield token_text
            return Response(generate(), mimetype="text/plain")
        else:
            response = llm(
                message,
                max_tokens=4096,
                temperature=0.6,
                top_p=0.95,
                top_k=40,
                stream=True,
                echo=False,
                stop=["<｜User｜>", "<｜Assistant｜>"]
            )
            text = response.get("choices", [{}])[0].get("text", "").strip()
            return jsonify({"response": text})
    except Exception as e:
        return jsonify({"error": f"Exception: {e}"}), 500

if __name__ == "__main__":
    print(f"Starting LLM server on {args.host}:{args.port} using model {args.model_path}")
    app.run(host=args.host, port=args.port, debug=False)
