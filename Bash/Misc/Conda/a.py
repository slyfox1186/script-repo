#!/usr/bin/env python3
"""
LLM Server for GeForce 3080 Ti using model_3090.gguf (Streaming Enabled)
"""

import sys
import json
import os
from flask import Flask, request, jsonify, Response
from flask_cors import CORS
from llama_cpp import Llama

app = Flask(__name__)
CORS(app)

# System prompts for reasoning levels
SYSTEM_PROMPT_LOW = """You are Debater A in a debate. Respond directly to the previous message from Debater B.
Focus on the logical structure of the arguments presented."""
SYSTEM_PROMPT_MEDIUM = """You are Debater A in a debate. Respond directly to the previous message from Debater B.
Analyze the logical structure of the arguments and identify strengths and weaknesses."""
SYSTEM_PROMPT_HIGH = """You are Debater A in a debate. Respond directly to the previous message from Debater B.
Provide a thorough analysis of the logical structure and reasoning patterns in the previous arguments."""

def create_llm():
    try:
        model_path = "./models/model_3090.gguf"
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model file not found at {model_path}")
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
        reasoning_level = data.get("reasoning_level", "medium").lower()
        system_prompt = {
            "low": SYSTEM_PROMPT_LOW,
            "medium": SYSTEM_PROMPT_MEDIUM,
            "high": SYSTEM_PROMPT_HIGH
        }.get(reasoning_level, SYSTEM_PROMPT_MEDIUM)
        formatted_message = f"{system_prompt}\n\n{message}"

        stream_flag = data.get("stream", False)
        if stream_flag:
            def generate():
                yield "data: {\"event\": \"start\", \"token\": \"\"}\n\n"
                last_token = ""
                for token_data in llm(
                    formatted_message,
                    max_tokens=2048,
                    temperature=0.7,
                    top_p=0.95,
                    top_k=40,
                    stream=True,
                    echo=False,
                    stop=["<｜User｜>", "<｜Assistant｜>"]
                ):
                    token_text = token_data["choices"][0].get("text", "") if isinstance(token_data, dict) else str(token_data)
                    if token_text:
                        if last_token and last_token[-1].isalnum() and token_text[0].isalnum() and not last_token.endswith(" "):
                            token_text = " " + token_text
                        yield f"data: {json.dumps({'event': 'token', 'token': token_text})}\n\n"
                        last_token = token_text
                yield f"data: {json.dumps({'event': 'message', 'message': last_token})}\n\n"
                yield "data: {\"event\": \"end\", \"token\": \"\"}\n\n"

            return Response(generate(), mimetype="text/event-stream", headers={
                'Cache-Control': 'no-cache',
                'X-Accel-Buffering': 'no',
                'Connection': 'keep-alive'
            })
        else:
            response = llm(formatted_message, max_tokens=2048, temperature=0.7, top_p=0.95, top_k=40, echo=False)
            return jsonify({"response": response["choices"][0]["text"].strip()})

    except Exception as e:
        return jsonify({"error": f"Exception: {e}"}), 500

if __name__ == "__main__":
    host = "0.0.0.0"
    port = 5001
    print(f"Starting LLM server on {host}:{port} using model_3090.gguf")
    app.run(host=host, port=port, debug=False, threaded=True)
