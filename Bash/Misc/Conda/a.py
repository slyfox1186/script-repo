#!/usr/bin/env python3
"""
LLM Server for GeForce 3080 Ti using model_3090.gguf (Streaming Enabled)
========================================================================

This server exposes a /chat API endpoint that generates responses using the 
model_3090.gguf model (GGUF format) via llama-cpp-python. It supports streaming 
mode via Server-Sent Events (SSE) when the request payload includes "stream": true.

Usage:
    python3 llm_server_3080.py

The server uses the model at ./models/model_3090.gguf and binds to 0.0.0.0:5001.
"""

import sys
import json
import os
from flask import Flask, request, jsonify, Response
from flask_cors import CORS
from llama_cpp import Llama

app = Flask(__name__)
CORS(app)

SYSTEM_PROMPT_LOW = """You are Debater A in a debate. Respond directly to the previous message from Debater B.
Focus on the logical structure of the arguments presented."""

SYSTEM_PROMPT_MEDIUM = """You are Debater A in a debate. Respond directly to the previous message from Debater B.
Analyze the logical structure of the arguments and identify strengths and weaknesses."""

SYSTEM_PROMPT_HIGH = """You are Debater A in a debate. Respond directly to the previous message from Debater B.
Provide a thorough analysis of the logical structure and reasoning patterns in the previous arguments."""

SYSTEM_PROMPT = SYSTEM_PROMPT_MEDIUM

def create_llm():
    try:
        model_path = "./models/model_3090.gguf"
        cpu_threads = os.cpu_count()
        return Llama(
            model_path=model_path, 
            n_ctx=8192,
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
        if not message.startswith("You are a helpful AI assistant participating in a debate. "):
            formatted_message = message
        else:
            formatted_message = message
        
        stream_flag = data.get("stream", False)
        if stream_flag:
            def generate():
                yield "data: {\"token\": \"\", \"event\": \"start\"}\n\n"
                try:
                    last_token = ""
                    for token_data in llm(
                        formatted_message,
                        max_tokens=2048,
                        temperature=0.6,
                        top_p=0.95,
                        top_k=40,
                        stream=True,
                        echo=False,
                        stop=["<｜User｜>", "<｜Assistant｜>"]
                    ):
                        if isinstance(token_data, dict):
                            if "choices" in token_data and len(token_data["choices"]) > 0:
                                token_text = token_data["choices"][0].get("text", "")
                            else:
                                token_text = token_data.get("token", "")
                        else:
                            token_text = str(token_data)
                        if token_text:
                            if last_token and token_text:
                                last_char = last_token[-1] if last_token else ""
                                first_char = token_text[0] if token_text else ""
                                if (last_char.isalnum() and first_char.isalnum() and 
                                    not last_token.endswith(' ') and not token_text.startswith(' ')):
                                    token_text = ' ' + token_text
                            yield f"data: {json.dumps({'token': token_text})}\n\n"
                            last_token = token_text
                    yield "data: {\"token\": \"\", \"event\": \"end\"}\n\n"
                except Exception as e:
                    print(f"Error in generate: {e}", file=sys.stderr)
                    error_data = json.dumps({"error": str(e)})
                    yield f"data: {error_data}\n\n"
                    yield "data: {\"token\": \"\", \"event\": \"end\"}\n\n"
            response = Response(generate(), mimetype="text/event-stream")
            response.headers.update({
                'Cache-Control': 'no-cache',
                'X-Accel-Buffering': 'no',
                'Connection': 'keep-alive',
                'Content-Type': 'text/event-stream',
                'Transfer-Encoding': 'chunked'
            })
            return response
        else:
            full_response = ""
            last_token = ""
            for token_data in llm(
                formatted_message,
                max_tokens=None,
                temperature=0.6,
                top_p=0.95,
                top_k=40,
                stream=True,
                echo=False,
                stop=["<｜User｜>", "<｜Assistant｜>"]
            ):
                if isinstance(token_data, dict):
                    if "choices" in token_data and len(token_data["choices"]) > 0:
                        token_text = token_data["choices"][0].get("text", "")
                    else:
                        token_text = token_data.get("token", "")
                else:
                    token_text = str(token_data)
                if token_text:
                    if last_token && token_text:
                        last_char = last_token[-1] if last_token else ""
                        first_char = token_text[0] if token_text else ""
                        if (last_char.isalnum() and first_char.isalnum() and 
                            not last_token.endswith(' ') and not token_text.startswith(' ')):
                            token_text = ' ' + token_text
                    full_response += token_text
                    last_token = token_text
            return jsonify({"response": full_response.strip()})
    except Exception as e:
        return jsonify({"error": f"Exception: {e}"}), 500

if __name__ == "__main__":
    model_path = "./models/model_3090.gguf"
    host = "0.0.0.0"
    port = 5001
    print(f"Starting LLM server on {host}:{port} using model {model_path}")
    app.run(host=host, port=port, debug=False, threaded=True)
