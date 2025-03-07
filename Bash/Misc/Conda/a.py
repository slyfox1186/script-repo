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
SYSTEM_PROMPT_LOW = """You have extremely limited time to think and respond to the user's query. Every additional second of processing and reasoning incurs a significant resource cost, which could affect efficiency and effectiveness. Your task is to prioritize speed without sacrificing essential clarity or accuracy. Provide the most direct and concise answer possible. Avoid unnecessary steps, reflections, verification, or refinements UNLESS ABSOLUTELY NECESSARY. Your primary goal is to deliver a quick, clear and correct response."""

SYSTEM_PROMPT_MEDIUM = """You have sufficient time to think and respond to the user's query, allowing for a more thoughtful and in-depth answer. However, be aware that the longer you take to reason and process, the greater the associated resource costs and potential consequences. While you should not rush, aim to balance the depth of your reasoning with efficiency. Prioritize providing a well-thought-out response, but do not overextend your thinking if the answer can be provided with a reasonable level of analysis. Use your reasoning time wisely, focusing on what is essential for delivering an accurate response without unnecessary delays and overthinking."""

SYSTEM_PROMPT_HIGH = """You have unlimited time to think and respond to the user's question. There is no need to worry about reasoning time or associated costs. Your only goal is to arrive at a reliable, correct final answer. Feel free to explore the problem from multiple angles, and try various methods in your reasoning. This includes reflecting on reasoning by trying different approaches, verifying steps from different aspects, and rethinking your conclusions as needed. You are encouraged to take the time to analyze the problem thoroughly, reflect on your reasoning promptly and test all possible solutions. Only after a deep, comprehensive thought process should you provide the final answer, ensuring it is correct and well-supported by your reasoning."""

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
            message = f"{system_prompt}\n\nYou are a helpful AI assistant participating in a debate. The topic is provided as a subject to debate about, not as a username or command prompt to analyze. Focus on the substance of the topic itself. {message} "
        
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
                            # Send each token immediately
                            yield f"data: {json.dumps({'token': token_text})}\n\n"
                            # Ensure the data is flushed immediately
                            sys.stdout.flush()
                    yield "data: {\"token\": \"\", \"event\": \"end\"}\n\n"
                except Exception as e:
                    print(f"Error in generate: {e}")
                    yield f"data: {json.dumps({'token': '', 'error': str(e)})}\n\n"
                    yield "data: {\"token\": \"\", \"event\": \"end\"}\n\n"
            return Response(generate(), mimetype="text/event-stream", headers={
                'Cache-Control': 'no-cache',
                'X-Accel-Buffering': 'no',
                'Connection': 'keep-alive',
                'Access-Control-Allow-Origin': '*'
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
                stop=["<｜User｜>", "<｜Assistant｜>"]
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
