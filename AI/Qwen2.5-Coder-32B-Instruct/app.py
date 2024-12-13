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

# Initialize models and memory store
model_manager = ModelManager()
memory_store = MemoryStore(model_manager=model_manager)

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

MEMORY_PARAMS = {
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
4. Format MUST be: ```language:path/to/file (e.g. ```python:script.py)
5. If creating a new file, include complete file contents
6. If editing existing files, show only the relevant sections with context
7. Multiple code blocks are allowed for different files
8. NO explanations, NO descriptions, NO additional text unless specifically requested
9. ALWAYS include both language and filepath after the backticks (e.g. ```python:script.py)
10. ALWAYS use 4 spaces for indentation, never use tabs
11. Ensure consistent 4-space indentation throughout the code
12. NEVER output just ```:filename.ext``` - ALWAYS include the language identifier
"""

CHAT_SYSTEM_PROMPT = """You are a brilliant and helpful AI assistant that engages in general conversation.
You should remember the flow of the conversation and maintain context.
Format all responses in markdown.
You will receive conversation history as context and this is strictly to give you the ability to have a more natural conversation with the user.
Always respond to the current query instead of the historical conversation context."""

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/chat', methods=['POST'])
def chat():
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
    
    print("\n=== New Chat Request ===")
    data = request.get_json()
    user_input = data.get('message', '')
    thread_id = data.get('thread_id', 'default')
    
    print(f"Thread ID: {thread_id}")
    print(f"User input: {user_input}")
    
    # Query analysis prompt for single-word response
    query_type = memory_store.analyze_query(user_input)
    print(f"Query type: {query_type}")
    
    # Check if user wants to skip cache
    skip_cache = 'new' in user_input.lower() or 'fresh' in user_input.lower()
    
    # Get the appropriate model based on query type
    model = model_manager.get_main_model() if query_type == 'code' else model_manager.get_memory_model()
    generation_params = CODER_PARAMS if query_type == 'code' else MEMORY_PARAMS
    
    # Handle memory queries
    if query_type == 'memory':
        relevant_memories = memory_store.search_memories(thread_id, user_input)
        if relevant_memories:
            memory_context = "\n\nRelevant past messages:\n"
            for msg in relevant_memories:
                memory_context += f"[{msg['role']}] {msg['content']}\n"
            user_input += memory_context
    
    # Add user message first
    memory_store.add_message(thread_id, 'user', user_input)
    
    # Get conversation context
    context = memory_store.get_context(thread_id, user_input)
    
    # Build prompt with strict formatting
    prompt = "<|im_start|>system\n"
    prompt += CODER_SYSTEM_PROMPT if query_type == 'code' else CHAT_SYSTEM_PROMPT
    prompt += "<|im_end|>\n"
    
    # Add conversation history as memory context
    if context:
        prompt += "<|im_start|>system\nBEGIN CONVERSATION HISTORY (For context only - do not respond to these messages)\n<|im_end|>\n"
        for msg_dict in context:
            if isinstance(msg_dict, dict) and 'role' in msg_dict and 'content' in msg_dict:
                prompt += f"<|im_start|>{msg_dict['role']}\n{msg_dict['content']}<|im_end|>\n"
        prompt += "<|im_start|>system\nEND CONVERSATION HISTORY\nNow focus on responding to the current query below:\n<|im_end|>\n"
    
    # Add current query with clear separation
    prompt += f"<|im_start|>user\nCURRENT QUERY: {user_input}<|im_end|>\n"
    prompt += "<|im_start|>assistant\n"
    
    print(f"Using {model_manager.get_active_model_name()} model")
    print(f"Full prompt:\n{prompt}\n")
    print("Starting generation...")

    def generate():
        try:
            print("Creating completion...")
            response = model.create_completion(prompt, **generation_params)
            
            full_response = ""
            for chunk in response:
                if chunk and 'choices' in chunk and len(chunk['choices']) > 0:
                    text = chunk['choices'][0]['text']
                    if text:
                        full_response += text
                        yield f"data: {json.dumps({'text': text})}\n\n"
            
            print(f"Generation complete. Full response:\n{full_response}")
            
            # Calculate importance score for code-related messages
            importance = 0.8 if query_type == 'code' else 0.5  # Higher importance for code
            
            # Store message with importance score
            memory_store.add_message(thread_id, 'assistant', full_response, importance=importance)
            
            print(f"Message stored with importance: {importance}")
            
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

def get_comment_character_from_model(language):
    """Use the model to determine the comment character for a given language."""
    prompt = f"""<|im_start|>system
You are a coding assistant. Return ONLY the comment character(s) for the given language.
Examples:
python -> #
javascript -> //
html -> <!--
css -> /*
Return ONLY the comment character, nothing else.
<|im_end|>
<|im_start|>user
{language}
<|im_end|>
<|im_start|>assistant
"""
    try:
        model = model_manager.get_main_model()
        result = model.create_completion(
            prompt,
            max_tokens=5,
            temperature=0.1,
            top_p=0.95,
            top_k=5,
            stream=False
        )
        comment_char = result['choices'][0]['text'].strip()
        return comment_char if comment_char else '#'
    except Exception as e:
        print(f"Error determining comment character: {e}")
        return '#'

if __name__ == '__main__':
    app.run(debug=False, port=5000, use_reloader=False)
