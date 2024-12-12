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
    
    # Use memory model to analyze query type and intent
    query_analysis_prompt = (
        "<|im_start|>system\n"
        "You analyze user queries to determine:\n"
        "1. If the query is code-related (requesting code, programming help, etc)\n"
        "2. If they want fresh code generation instead of cached responses\n"
        "Return ONLY in this format: 'code:true/false,fresh:true/false'\n"
        "<|im_end|>\n"
        "<|im_start|>user\n"
        f"Analyze this request:\n\n{user_input}\n"
        "<|im_end|>\n"
        "<|im_start|>assistant\n"
    )
    
    try:
        analysis = model_manager.get_memory_model().create_completion(
            query_analysis_prompt,
            max_tokens=10,
            temperature=0.1,
            top_p=0.05,
            top_k=2,
            stream=False
        )
        
        result = analysis['choices'][0]['text'].strip().lower()
        code_part, fresh_part = result.split(',')
        is_code_related = code_part.split(':')[1] == 'true'
        skip_cache = fresh_part.split(':')[1] == 'true'
        
        print(f"Query analysis - Code related: {is_code_related}, Skip cache: {skip_cache}")
    except Exception as e:
        print(f"Analysis failed, defaulting to conservative values: {e}")
        is_code_related = False
        skip_cache = False
    
    # Define generation parameters for each model type
    CODER_PARAMS = {
        'max_tokens': None,
        'temperature': 0.2,      # Low temperature for consistent outputs
        'top_p': 0.10,           # Very focused sampling
        'top_k': 20,             # Limited token selection
        'repeat_penalty': 1.1,   # Slight penalty for repetition
        'presence_penalty': 0,   # No presence penalty for code
        'frequency_penalty': 0,  # No frequency penalty for code
        'echo': False,
        'stream': True
    }
    
    MEMORY_PARAMS = {
        'max_tokens': None,
        'temperature': 0.8,       # Higher temperature for creativity
        'top_p': 0.95,            # More diverse sampling
        'top_k': 50,              # Broader token selection
        'repeat_penalty': 1.15,   # Stronger repetition avoidance
        'presence_penalty': 0.25, # Encourage topic exploration
        'frequency_penalty': 0.3, # Encourage vocabulary diversity
        'echo': False,
        'stream': True
    }
    
    # Check cache only for code-related queries and when not explicitly asked to skip
    if is_code_related and not skip_cache:
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
    
    # Select appropriate model, parameters, and system prompt
    if is_code_related:
        model = model_manager.get_main_model()
        generation_params = CODER_PARAMS
        system_prompt = (
            "You are a code-focused AI assistant that writes clean, efficient code.\n"
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
        generation_params = MEMORY_PARAMS
        system_prompt = (
            "You are a brilliant and helpful AI assistant that engages in general conversation.\n"
            "You should remember the flow of the conversation and maintain context.\n"
            "Format all responses in markdown.\n"
            "You will receive conversation history as context and this is strictly to give you the ability to have a more natural conversation with the user.\n"
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
    
    print(f"Using {'Qwen Coder' if is_code_related else 'Memory'} model with appropriate parameters")
    print(f"Full prompt:\n{prompt}\n")
    print("Starting generation...")

    def generate():
        try:
            print("Creating completion...")
            response = model.create_completion(prompt, **generation_params)
            print("Got response object")
            
            full_response = ""
            for chunk in response:
                print(f"Raw chunk: {chunk}")
                if chunk and 'choices' in chunk and len(chunk['choices']) > 0:
                    text = chunk['choices'][0]['text']
                    if text:
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
