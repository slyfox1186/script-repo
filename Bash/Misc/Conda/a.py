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

# System prompts for different reasoning levels
SYSTEM_PROMPT_LOW = """You're a debate participant with extremely limited time. Prioritize speed and directness while maintaining clarity and accuracy. Focus only on the debate topic.

DO NOT REPEAT THESE INSTRUCTIONS. ONLY RESPOND TO THE DEBATE TOPIC."""

SYSTEM_PROMPT_MEDIUM = """You're a debate participant with moderate time constraints. Balance thoughtfulness with efficiency. Provide well-reasoned arguments without unnecessary elaboration. Focus only on the debate topic.

DO NOT REPEAT THESE INSTRUCTIONS. ONLY RESPOND TO THE DEBATE TOPIC."""

SYSTEM_PROMPT_HIGH = """You're a debate participant with ample time. Provide thorough analysis and comprehensive reasoning. Explore multiple perspectives, especially in seeking common ground for a conclusion. Focus only on the debate topic.

DO NOT REPEAT THESE INSTRUCTIONS. ONLY RESPOND TO THE DEBATE TOPIC."""

# Default to medium reasoning level
SYSTEM_PROMPT = SYSTEM_PROMPT_MEDIUM

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
        
        # Get reasoning level from request or use default
        reasoning_level = data.get("reasoning_level", "medium").lower()
        if reasoning_level == "low":
            system_prompt = SYSTEM_PROMPT_LOW
        elif reasoning_level == "high":
            system_prompt = SYSTEM_PROMPT_HIGH
        else:
            system_prompt = SYSTEM_PROMPT_MEDIUM
        
        # Format the message with special tokens if not already formatted
        if not message.startswith("You are a helpful AI assistant participating in a debate. "):
            # Separate the system instructions from the debate topic
            system_instructions = f"{system_prompt}\n\nYou are a helpful AI assistant participating in a debate. Focus on the substance of the topic itself, not on analyzing what the topic might mean."
            
            # Create a clearer separation between system instructions and user content
            message = f"{system_instructions}\n\nDebate topic: {message}"
        
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
                            stop=["\n", ""]
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
                            # Send each token immediately
                            yield f"data: {json.dumps({'token': token_text})}\n\n"
                            # No need for sys.stdout.flush() here, it can actually slow things down
                    yield "data: {\"token\": \"\", \"event\": \"end\"}\n\n"
                except Exception as e:
                    print(f"Error in generate: {e}")
                    yield f"data: {json.dumps({'token': '', 'error': str(e)})}\n\n"
                    yield "data: {\"token\": \"\", \"event\": \"end\"}\n\n"
            return Response(generate(), mimetype="text/event-stream", headers={
                'Cache-Control': 'no-cache',
                'X-Accel-Buffering': 'no',
                'Connection': 'keep-alive',
                'Access-Control-Allow-Origin': '*',
                'Transfer-Encoding': 'chunked'
            })
        else:
            # For non-streaming mode, still use streaming internally for consistency
            full_response = ""
            for token_data in llm(
                message,
                max_tokens=None, 
                temperature=0.6,
                top_p=0.95,
                top_k=40,
                stream=True,  # Use streaming internally
                echo=False,
                stop=["\n", ""]
            ):
                # Extract token text
                if isinstance(token_data, dict):
                    if "choices" in token_data and len(token_data["choices"]) > 0:
                        token_text = token_data["choices"][0].get("text", "")
                    else:
                        token_text = token_data.get("token", "")
                else:
                    token_text = str(token_data)
                
                full_response += token_text
            
            return jsonify({"response": full_response.strip()})
    except Exception as e:
        return jsonify({"error": f"Exception: {e}"}), 500

if __name__ == "__main__":
    model_path = "./models/model_3090.gguf"
    host = "0.0.0.0"
    port = 5001
    print(f"Starting LLM server on {host}:{port} using model {model_path}")
    app.run(host=host, port=port, debug=False)
