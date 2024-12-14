#!/usr/bin/env python3

import json
import os
import torch
from datetime import datetime
from flask import Flask, render_template, request, jsonify, Response
from llama_cpp import Llama
from pathlib import Path
from persistent_memory import ModelManager, MemoryStore
import traceback

app = Flask(__name__)

# Initialize models and memory store
try:
    print("Initializing model manager...")
    model_manager = ModelManager()
    print("Initializing memory store...")
    memory_store = MemoryStore(model_manager=model_manager)
    print("Initialization complete")
except Exception as e:
    print(f"Error during initialization: {str(e)}")
    raise

CODER_PARAMS = {
    'max_tokens': None,
    'temperature': 0.17,
    'top_p': 0.12,
    'top_k': 23,
    'repeat_penalty': 1.12,
    'presence_penalty': 0,
    'frequency_penalty': 0,
    'echo': False,
    'stream': True
}

CHAT_PARAMS = {
    'max_tokens': None,
    'temperature': 0.83,
    'top_p': 0.95,
    'top_k': 53,
    'repeat_penalty': 1.15,
    'presence_penalty': 0.23,
    'frequency_penalty': 0.27,
    'echo': False,
    'stream': True
}

CODER_SYSTEM_PROMPT = """You are a code-focused AI assistant that writes clean, efficient code.
IMPORTANT INSTRUCTIONS:
1. Provide ONLY the code implementation unless explicitly asked for explanations
2. Use markdown code blocks with appropriate language tags and file paths
3. Use comments to indicate unchanged code sections
4. Format: ```language:path/to/file\n{code}\n```
5. If creating a new file, include complete file contents
6. If editing existing files, show only the relevant sections with context
7. Multiple code blocks are allowed for different files
8. NO explanations, NO descriptions, NO additional text unless specifically requested
9. DO NOT add commented filepath at start of code - the client will handle this
10. ALWAYS use 4 spaces for indentation, never use tabs
11. Ensure consistent 4-space indentation throughout the code
"""

CHAT_SYSTEM_PROMPT = """You are a helpful AI assistant. Respond naturally and conversationally.
If the user asks about code or programming, let them know you'll switch to coding mode.
Otherwise, engage in natural dialogue while remembering context from previous messages."""

ROUTER_SYSTEM_PROMPT = """You are a router that decides which AI model should handle the user's request.
If the user is asking for code help, programming assistance, or explicitly requesting the coder model, respond with exactly "CODER".
If the user is making general conversation, asking questions, or explicitly requesting the smaller model, respond with exactly "CHAT".
Respond ONLY with one of these two words, nothing else.
Examples:
- "Show me a Python script" -> "CODER"
- "How are you today?" -> "CHAT"
- "Coder are you there?" -> "CODER"
- "Small model please respond" -> "CHAT"
"""

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/chat', methods=['POST'])
def chat():
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
    
    try:
        data = request.get_json()
        user_input = data.get('message', '')
        thread_id = data.get('thread_id', 'default')
        
        # First, use the small model to route the request
        router_prompt = "<|im_start|>system\n"
        router_prompt += f"{ROUTER_SYSTEM_PROMPT}<|im_end|>\n"
        router_prompt += f"<|im_start|>user\n{user_input}<|im_end|>\n"
        router_prompt += "<|im_start|>assistant\n"
        
        # Use memory model for routing decision
        router_model = model_manager.get_memory_model()
        router_response = router_model.create_completion(
            router_prompt,
            max_tokens=1,
            temperature=0,
            stop=["<|im_end|>"],
            stream=False
        )
        
        # Extract routing decision from dictionary response
        model_choice = router_response['choices'][0]['text'].strip()
        model_type = "coder" if model_choice == "CODER" else "chat"
        
        print(f"\n=== PROCESSING CHAT ===")
        print(f"User input: {user_input}")
        print(f"Thread ID: {thread_id}")
        print(f"Router decision: {model_choice}")
        print(f"Model type: {model_type}")
        
        # Store user message
        memory_store.add_message(thread_id, 'user', user_input)
        
        # Get context and continue with chosen model
        context = memory_store.get_context(thread_id, user_input)
        if isinstance(context, list):
            context = "\n".join(context)
        
        # Build prompt with correct system prompt based on model type
        system_prompt = CODER_SYSTEM_PROMPT if model_type == "coder" else CHAT_SYSTEM_PROMPT
        
        # Build the full prompt following the format
        full_prompt = f"<|im_start|>system\n{system_prompt}<|im_end|>\n"
        full_prompt += f"<|im_start|>user\n{context}{user_input}<|im_end|>\n"
        full_prompt += "<|im_start|>assistant\n"
        
        # Select model and parameters
        model = model_manager.get_coder_model() if model_type == "coder" else model_manager.get_memory_model()
        generation_params = CODER_PARAMS if model_type == "coder" else CHAT_PARAMS
        
        def generate():
            try:
                response = model.create_completion(full_prompt, **generation_params)
                for chunk in response:
                    if chunk:
                        text = chunk['choices'][0]['text']
                        yield f"data: {json.dumps({'text': text})}\n\n"
            except Exception as e:
                print(f"Generation error: {str(e)}")
                yield f"data: {json.dumps({'error': str(e)})}\n\n"
        
        return Response(generate(), mimetype='text/event-stream')
        
    except Exception as e:
        print(f"\n=== REQUEST ERROR ===")
        print(f"Error: {str(e)}")
        print(f"Stack trace: {traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/clear_thread', methods=['POST'])
def clear_thread():
    thread_id = request.json.get('thread_id')
    memory_store.clear_thread(thread_id)
    return jsonify({'status': 'success'})

@app.route('/get_threads', methods=['GET'])
def get_threads():
    return jsonify(memory_store.get_thread_ids())

@app.route('/clear_all_threads', methods=['POST'])
def clear_all_threads():
    """Clear all conversation threads"""
    try:
        print("\n=== Clear All Threads Request ===")
        success = memory_store.clear_thread('default')  # For now just clear default thread
        response = {
            'status': 'success' if success else 'error',
            'message': 'All conversations cleared' if success else 'Failed to clear conversations',
            'files_remaining': [f.name for f in Path("conversation_history").glob("*.json")]
        }
        print(f"Clear response: {response}")
        return jsonify(response)
    except Exception as e:
        error_response = {
            'status': 'error',
            'message': str(e)
        }
        print(f"Clear error: {error_response}")
        return jsonify(error_response), 500

if __name__ == '__main__':
    app.run(debug=False, port=5000, use_reloader=False)
