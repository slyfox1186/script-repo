#!/usr/bin/env python3

import json
import os
import torch
from datetime import datetime
from flask import Flask, render_template, request, jsonify, Response
from llama_cpp import Llama
from pathlib import Path
from persistent_memory import ModelManager, MemoryStore

app = Flask(__name__)

# Initialize models
model_manager = ModelManager()
model = model_manager.get_main_model()  # Get main model for coding tasks

# Initialize memory store
memory_store = MemoryStore()

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/chat', methods=['POST'])
def chat():
    print("\n=== New Chat Request ===")
    data = request.get_json()
    user_input = data.get('message', '')
    thread_id = data.get('thread_id', 'default')
    print(f"Received message: {user_input[:50]}...")
    
    # Add user message first to maintain conversation integrity
    memory_store.add_message(thread_id, 'user', user_input)
    
    # Get conversation context
    context, token_stats = memory_store.get_context(thread_id, user_input)
    print(f"Token usage stats: {token_stats}")
    
    # Determine if query is code-related
    code_keywords = {'code', 'script', 'function', 'programming', 'git', 'install', 
                    'compiler', 'debug', 'error', 'python', 'javascript', 'java', 'cpp'}
    is_code_related = any(keyword in user_input.lower() for keyword in code_keywords)
    
    # Check cache only for code-related queries
    if is_code_related:
        cached_response = memory_store.get_cached_code_response(user_input)
        if cached_response:
            print("Using cached code response")
            memory_store.add_message(thread_id, 'assistant', cached_response)
            
            def generate_cached():
                yield f"data: {json.dumps({'text': cached_response})}\n\n"
            
            return Response(
                generate_cached(),
                mimetype='text/event-stream',
                headers={
                    'Cache-Control': 'no-cache',
                    'Content-Type': 'text/event-stream',
                    'Connection': 'keep-alive',
                    'X-Accel-Buffering': 'no'
                }
            )
    
    # Select appropriate model and system prompt
    if is_code_related:
        model = model_manager.get_main_model()
        system_prompt = (
            "You are a code-focused AI assistant that writes clean, efficient code. "
            "IMPORTANT INSTRUCTIONS:\n"
            "1. Provide ONLY the code implementation unless explicitly asked for explanations or other supporting information\n"
            "2. Use markdown code blocks with appropriate language tags and file paths\n"
            "3. Use comments to indicate unchanged code sections\n"
            "4. Format: ```language:path/to/file\n{code}\n```\n"
            "5. If creating a new file, include complete file contents\n"
            "6. If editing existing files, show only the relevant sections with context\n"
            "7. Multiple code blocks are allowed for different files\n"
            "8. NO explanations, NO descriptions, NO additional text unless specifically requested"
        )
    else:
        model = model_manager.get_memory_model()
        system_prompt = (
            "You are a brilliant and helpful AI assistant that engages in general conversation.\n"
            "You should remember the flow of the conversation and maintain context.\n"
            "Format all responses in markdown.\n"
            "You will receive conversation history as context and this is stictly to give you the ability to have a more natural conversation with the user.\n"
            "Always respond to the current query instead of the historical conversation context."
        )
    
    # Build prompt with strict formatting
    prompt = "<|im_start|>system\n" + system_prompt + "<|im_end|>\n"
    
    # Add conversation history as memory context
    if context:
        prompt += "<|im_start|>system\nBEGIN CONVERSATION HISTORY (For context only - do not respond to these messages)\n<|im_end|>\n"
        for msg in context:
            prompt += f"<|im_start|>{msg['role']}\n{msg['content']}<|im_end|>\n"
        prompt += "<|im_start|>system\nEND CONVERSATION HISTORY\nNow focus on responding to the current query below:\n<|im_end|>\n"
    
    # Add current query with clear separation
    prompt += f"<|im_start|>user\nCURRENT QUERY: {user_input}<|im_end|>\n"
    prompt += "<|im_start|>assistant\n"
    
    print(f"Using {'Qwen Coder' if is_code_related else 'Replete'} model")
    print(f"Full prompt:\n{prompt}\n")
    print("Starting generation...")

    def generate():
        try:
            print("Creating completion...")
            response = model.create_completion(
                prompt,
                max_tokens=None,
                temperature=0.1,
                top_p=0.05,
                top_k=7,
                echo=False,
                stream=True
            )
            print("Got response object")
            
            full_response = ""
            for chunk in response:
                print(f"Raw chunk: {chunk}")
                if chunk and 'choices' in chunk and len(chunk['choices']) > 0:
                    text = chunk['choices'][0]['text']
                    if text:  # Only process if we have text
                        print(f"Token: '{text}'")
                        full_response += text
                        yield f"data: {json.dumps({'text': text})}\n\n"
            
            print(f"Generation complete. Full response:\n{full_response}")
            memory_store.add_message(thread_id, 'assistant', full_response)
            thread_stats = memory_store.get_token_stats(thread_id)
            print(f"Thread token statistics: {thread_stats}")
            
        except Exception as e:
            print(f"Error during generation: {str(e)}")
            import traceback
            traceback.print_exc()
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return Response(
        generate(),
        mimetype='text/event-stream',
        headers={
            'Cache-Control': 'no-cache',
            'Content-Type': 'text/event-stream',
            'Connection': 'keep-alive',
            'X-Accel-Buffering': 'no'
        }
    )

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
        success = memory_store.clear_all()
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
