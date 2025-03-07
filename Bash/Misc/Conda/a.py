#!/usr/bin/env python3
"""
LLM Server for GeForce 3080 Ti using DeepSeek-R1-Distill-Qwen-14B (Streaming Enabled)
========================================================================================

This server exposes a /chat API endpoint for generating responses using the 
DeepSeek-R1-Distill-Qwen-14B model (GGUF format) via llama-cpp-python. 
Streaming mode is supported via Server-Sent Events (SSE) when "stream": true is provided in the request.

Usage:
    python3 llm_server_3080.py

The server will use the model at ./models/model_3090.gguf and bind to 0.0.0.0:5001.
"""

import sys
import json
import os
from flask import Flask, request, jsonify, Response
from flask_cors import CORS
from llama_cpp import Llama

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

def create_llm():
    try:
        model_path = "./models/model_3090.gguf"
        cpu_threads = os.cpu_count()
        return Llama(model_path=model_path, n_gpu_layers=-1, n_threads=cpu_threads, verbose=True)
    except Exception as e:
        print(f"Error initializing LLM: {e}", file=sys.stderr)
        sys.exit(1)

llm = create_llm()

@app.route("/chat", methods=["POST"])
def chat():
    try:
        data = request.get_json()
        if not data or "message" not in data:
            return jsonify({"error": "No message provided"}), 400
        message = data["message"]
        stream_flag = data.get("stream", False)
        if stream_flag:
            def generate():
                # SSE format: each message is prefixed with "data: " and ends with two newlines
                yield "data: {\"token\": \"\", \"event\": \"start\"}\n\n"
                for token_data in llm(message, max_tokens=None, temperature=0.6, stream=True):
                    token_text = token_data.get("token", "")
                    yield f"data: {json.dumps({'token': token_text})}\n\n"
                yield "data: {\"token\": \"\", \"event\": \"end\"}\n\n"
            return Response(generate(), mimetype="text/event-stream", headers={
                'Cache-Control': 'no-cache',
                'X-Accel-Buffering': 'no',
                'Access-Control-Allow-Origin': '*'
            })
        else:
            response = llm(message, max_tokens=None, temperature=0.6)
            text = response.get("choices", [{}])[0].get("text", "").strip()
            return jsonify({"response": text})
    except Exception as e:
        return jsonify({"error": f"Exception: {e}"}), 500

if __name__ == "__main__":
    model_path = "./models/model_3090.gguf"
    host = "0.0.0.0"
    port = 5001
    print(f"Starting LLM server on {host}:{port} using model {model_path}")
    app.run(host=host, port=port, debug=False)
