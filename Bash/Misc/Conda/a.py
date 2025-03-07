#!/usr/bin/env python3
"""
LLM Server for GeForce 3080 Ti using model_3090.gguf (Streaming Enabled)
========================================================================

This server exposes a /chat API endpoint that generates responses using the 
model_3090.gguf model (GGUF format) via llama-cpp-python. It supports streaming 
mode via Server-Sent Events (SSE) when the request payload includes "stream": true.

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
        return Llama(
            model_path=model_path, 
            n_ctx=4096,
            n_threads=cpu_threads, 
            n_batch=512,
            main_gpu=0,
            n_gpu_layers=-1, 
            flash_attn=True,
            use_mmap=True,
            use_mlock=True,
            offload_kqv=True,
            verbose=True            
        )
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
        
        # Format the message with special tokens if not already formatted
        if not message.startswith("You are a helpful AI assistant participating in a debate. "):
            message = f"You are a helpful AI assistant participating in a debate. {message} "
        
        stream_flag = data.get("stream", False)
        if stream_flag:
            def generate():
                # SSE format: each message is prefixed with "data: " and ends with two newlines
                yield "data: {\"token\": \"\", \"event\": \"start\"}\n\n"
                try:
                    for token_data in llm(
                            message,
                            max_tokens=None, 
                            temperature=0.6,
                            top_p=0.95,
                            top_k=40,
                            stream=True,
                            echo=False,
                            stop=["<｜User｜>", "<｜Assistant｜>"]
                        ):
                        # Debug the token data
                        print(f"Token data: {token_data}")
                        
                        # Extract token text correctly based on the structure
                        if isinstance(token_data, dict):
                            if "choices" in token_data and len(token_data["choices"]) > 0:
                                token_text = token_data["choices"][0].get("text", "")
                            else:
                                token_text = token_data.get("token", "")
                        else:
                            token_text = str(token_data)
                            
                        if token_text:
                            print(f"Sending token: {token_text}")
                            yield f"data: {json.dumps({'token': token_text})}\n\n"
                    yield "data: {\"token\": \"\", \"event\": \"end\"}\n\n"
                except Exception as e:
                    print(f"Error in generate: {e}")
                    yield f"data: {json.dumps({'token': '', 'error': str(e)})}\n\n"
                    yield "data: {\"token\": \"\", \"event\": \"end\"}\n\n"
            return Response(generate(), mimetype="text/event-stream", headers={
                'Cache-Control': 'no-cache',
                'X-Accel-Buffering': 'no',
                'Access-Control-Allow-Origin': '*'
            })
        else:
            response = llm(
                message,
                max_tokens=None, 
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
    model_path = "./models/model_3090.gguf"
    host = "0.0.0.0"
    port = 5001
    print(f"Starting LLM server on {host}:{port} using model {model_path}")
    app.run(host=host, port=port, debug=False)
