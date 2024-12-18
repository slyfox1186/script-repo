#!/usr/bin/env python3

import atexit
import json
import logging
import os
import signal
import sys
import time
import torch
import traceback
from datetime import datetime
from flask import Flask, render_template, request, jsonify, Response, send_from_directory
from llama_cpp import Llama
from pathlib import Path
from persistent_memory import (
    Application, 
    UnifiedState, 
    ModelConfig, 
    MAX_CONTEXT_TOKENS_SMALL, 
    MAX_CONTEXT_TOKENS_LARGE,
    MAX_GENERATION_TOKENS
)
from prompts import (
    LM_SMALL_SYSTEM_PROMPT,
    LM_LARGE_SYSTEM_PROMPT
)
from common.logging import setup_logger
from ai_converse import create_conversation_manager, ConversationConfig
import threading
from concurrent.futures import ThreadPoolExecutor
from functools import wraps
import uuid
import gc
import psutil
from typing import Optional, Tuple
from dataclasses import dataclass
from contextlib import contextmanager

# Initialize Flask app
app = Flask(__name__)

# Setup logging with minimal output
logger = setup_logger(__name__, level=logging.DEBUG)

# Disable Flask's default logging
app.logger.disabled = True
logging.getLogger('werkzeug').disabled = True

# Disable llama-cpp verbose logging
os.environ['LLAMA_CPP_VERBOSE'] = '0'

# Initialize application state
storage_path = Path("conversation_history").absolute()
storage_path.mkdir(parents=True, exist_ok=True)
logger.info(f"Initializing storage at: {storage_path}")

# Create single application instance (singleton)
app_instance = Application()

# Set state for model manager
app_instance.model_manager.set_state(app_instance.state)

# No need to set model_manager separately since it's part of app_instance

# Initialize thread pool
thread_pool = ThreadPoolExecutor(max_workers=4)

# Global shutdown flag
shutdown_event = threading.Event()

# Health monitoring
health_stats = {
    'requests': 0,
    'errors': 0,
    'last_error': None,
    'start_time': time.time(),
    'model_switches': 0
}

def monitor_request():
    """Track request metrics"""
    health_stats['requests'] += 1
    
def monitor_error(error: Exception):
    """Track error metrics"""
    health_stats['errors'] += 1
    health_stats['last_error'] = str(error)

@app.route('/health', methods=['GET'])
def health_check():
    """API health check endpoint"""
    uptime = time.time() - health_stats['start_time']
    return jsonify({
        'status': 'healthy',
        'uptime': uptime,
        'requests': health_stats['requests'],
        'errors': health_stats['errors'],
        'error_rate': health_stats['errors'] / max(health_stats['requests'], 1),
        'last_error': health_stats['last_error'],
        'model_switches': health_stats['model_switches']
    })

@app.route('/')
def home():
    return render_template('index.html')

def save_response(response_buffer, thread_id, model_type=None):
    """Save response with fallback for model type"""
    logger.info("\n=== SAVE_RESPONSE [EXTREME VERBOSE] ===")
    logger.info(f"[SAVE] Thread ID: {thread_id}")
    logger.info(f"[SAVE] Model type: {model_type}")
    logger.info(f"[SAVE] Buffer type: {type(response_buffer)}")
    
    try:
        response_text = ''.join(response_buffer)
        logger.info(f"[SAVE] Combined response text: {response_text}")
        
        message = {
            'role': 'assistant',
            'content': response_text,
            'timestamp': time.time(),
            'thread_id': thread_id,
            'model_type': model_type or 'unknown'
        }
        logger.info(f"[SAVE] Created message object: {message}")
        
        success = app_instance.message_manager.add_message(message)
        logger.info(f"[SAVE] Message save result: {success}")
        
        # Verify save
        history = app_instance.conversation_manager.get_thread_history(thread_id)
        logger.info(f"[SAVE] History after save: {history}")
        
    except Exception as e:
        logger.error(f"[SAVE] Error: {e}")
        logger.error(f"[SAVE] Error type: {type(e)}")
        logger.error(traceback.format_exc())

@app.route('/chat', methods=['POST'])
def chat():
    logger.info("\n=== CHAT ENDPOINT [EXTREME VERBOSE] ===")
    try:
        data = request.get_json()
        logger.info(f"[CHAT] Raw request data: {data}")
        message = data.get('message', '').strip()
        thread_id = data.get('thread_id', 'default')
        
        # Check for model switch requests
        if message == '@nutonic' or message == '@charlotte' or message == '@lotte':
            success, switch_msg = app_instance.model_manager.determine_model_type(message)
            if success:
                switch_text = "Switching to Nutonic (LM_LARGE)..." if message == '@nutonic' else "Switching to Charlotte (LM_SMALL)..."
                return Response(
                    f'data: {{"text": "{switch_text}"}}\ndata: [DONE]\n\n',
                    mimetype='text/event-stream'
                )
        
        def generate():
            try:
                # Initialize response buffer
                response_buffer = []
                
                # Store user message
                user_message = {
                    'role': 'user',
                    'content': message,
                    'timestamp': time.time(),
                    'thread_id': thread_id
                }
                app_instance.conversation_manager.add_message(thread_id, user_message)
                
                # Get model and generate response
                model = app_instance.model_manager.get_current_model()
                if not model:
                    yield f"data: {json.dumps({'error': 'No model loaded'})}\n\n"
                    return
                
                # Get context and check total tokens
                context = app_instance.context_manager.build_context(thread_id, message)
                context_tokens = app_instance.context_manager._count_tokens_accurately(context)
                
                # Calculate safe generation limit
                max_safe_generation = min(
                    4096,  # Maximum generation limit
                    MAX_GENERATION_TOKENS - 50  # Leave 50 token buffer
                )
                
                logger.info(f"[CHAT] Context tokens: {context_tokens}")
                logger.info(f"[CHAT] Safe generation limit: {max_safe_generation}")
                
                for chunk in model.create_completion(
                    context,
                    max_tokens=max_safe_generation,
                    temperature=0.7,
                    top_p=0.95,
                    top_k=40,
                    repeat_penalty=1.2,
                    stream=True,
                    stop=["<|im_end|>"]
                ):
                    if chunk and 'choices' in chunk:
                        text = chunk['choices'][0].get('text', '')
                        if text:
                            response_buffer.append(text)
                            # Send text event in format expected by client
                            yield f"data: {json.dumps({'text': text})}\n\n"
                
                # Save complete response
                if response_buffer:
                    complete_response = ''.join(response_buffer)
                    app_instance.conversation_manager.save_response(
                        response_buffer, 
                        thread_id,
                        model.model_type
                    )
                
                yield "data: [DONE]\n\n"
                
            except Exception as e:
                logger.error(f"Generation error: {e}")
                logger.error(traceback.format_exc())
                yield f"data: {json.dumps({'error': str(e)})}\n\n"
                yield "data: [DONE]\n\n"
        
        return Response(generate(), mimetype='text/event-stream')
        
    except Exception as e:
        logger.error(f"Chat endpoint error: {e}")
        logger.error(traceback.format_exc())
        return jsonify({'error': str(e)}), 500

def validate_chat_request(data) -> bool:
    """Validate chat request data"""
    try:
        if not data:
            logger.error("No request data provided")
            return False
            
        if not isinstance(data, dict):
            logger.error("Request data is not a dictionary")
            return False
            
        if 'message' not in data:
            logger.error("No message field in request")
            return False
            
        message = data['message']
        if not isinstance(message, str):
            logger.error("Message is not a string")
            return False
            
        if not message.strip():
            logger.error("Message is empty")
            return False
            
        return True
        
    except Exception as e:
        logger.error(f"Validation error: {e}")
        return False

@app.route('/clear_all_threads', methods=['POST'])
def clear_all_threads():
    """Clear all conversation threads"""
    try:
        logger.info("Clearing all conversation threads")
        
        # Clear all conversation state
        success = all([
            app_instance.message_manager.clear_all_threads(),  # Clear message history
            app_instance.conversation_manager.clear_all_threads(),  # Clear conversation threads
            app_instance.memory.clear_all(),  # Clear message memory
            True  # Add more clearing operations here if needed
        ])
        
        if success:
            logger.info("Successfully cleared all conversation state")
            return jsonify({"success": True, "message": "All conversations cleared"})
        else:
            logger.error("Failed to clear some conversation state")
            return jsonify({"success": False, "message": "Failed to clear all conversations"}), 500
            
    except Exception as e:
        logger.error(f"Error clearing threads: {e}")
        return jsonify({"error": str(e), "message": "An error occurred while clearing conversations"}), 500

@app.route('/model', methods=['GET', 'POST'])
def handle_model():
    """Handle model operations"""
    try:
        if request.method == 'GET':
            return jsonify({"model_type": app_instance.model_manager.get_current_model_type()})
        else:
            model_type = request.json.get('model_type')
            if not model_type or model_type not in ['memory', 'coder']:
                return jsonify({"error": "Invalid model type"}), 400
            success = app_instance.model_manager.set_active_model(model_type)
            return jsonify({"success": success})
    except Exception as e:
        logger.error(f"Model operation error: {e}")
        return jsonify({"error": str(e)}), 500

def async_task(func):
    """Decorator for async task execution"""
    @wraps(func)
    def wrapper(*args, **kwargs):
        return thread_pool.submit(func, *args, **kwargs)
    return wrapper

@async_task
def cleanup_handler(signum=None, frame=None):
    """Handle cleanup on shutdown"""
    # Add flag to prevent recursive cleanup
    if hasattr(cleanup_handler, 'is_cleaning'):
        return
    cleanup_handler.is_cleaning = True
    
    logger.info("Starting graceful shutdown")
    
    try:
        if app_instance:
            app_instance.cleanup()
        
        # Force clear CUDA memory
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            torch.cuda.synchronize()
            
        # Clear any remaining threads
        if thread_pool:
            thread_pool.shutdown(wait=False)
            
    except Exception as e:
        logger.error(f"Cleanup error: {e}")
        logger.error(traceback.format_exc())
    finally:
        logger.info("Shutdown complete")
        # Use sys.exit() instead of os._exit()
        sys.exit(0)

# Update signal handlers
signal.signal(signal.SIGINT, cleanup_handler)
signal.signal(signal.SIGTERM, cleanup_handler)

@app.route('/start_conversation', methods=['POST'])
def start_conversation():
    try:
        data = request.json
        if not data or 'topic' not in data:
            return jsonify({"error": "No topic provided"}), 400
            
        thread_id = data.get('thread_id', str(uuid.uuid4()))
        topic = data.get('topic')
        max_turns = data.get('max_turns', 10)
        
        config = ConversationConfig(
            max_turns=max_turns,
            topic=topic,
            temperature=data.get('temperature', 0.8),
            max_tokens=data.get('max_tokens', 1024),
            turn_delay=data.get('turn_delay', 2.0)
        )
        
        success = app_instance.conversation_manager.start_conversation(
            thread_id,
            topic,
            config
        )
        
        if success:
            return jsonify({
                "status": "success",
                "thread_id": thread_id,
                "message": f"Started conversation about: {topic}"
            })
        else:
            return jsonify({
                "error": "Failed to start conversation"
            }), 500
            
    except Exception as e:
        logger.error(f"Error starting conversation: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/stop_conversation', methods=['POST'])
def stop_conversation():
    try:
        data = request.json
        if not data or 'thread_id' not in data:
            return jsonify({"error": "No thread_id provided"}), 400
            
        thread_id = data['thread_id']
        success = app_instance.conversation_manager.stop_conversation(thread_id)
        
        if success:
            return jsonify({
                "status": "success",
                "message": "Conversation stopped"
            })
        else:
            return jsonify({
                "error": "Failed to stop conversation"
            }), 500
            
    except Exception as e:
        logger.error(f"Error stopping conversation: {e}")
        return jsonify({"error": str(e)}), 500

# Add new endpoint for injecting messages into conversations
@app.route('/inject_message', methods=['POST'])
def inject_message():
    try:
        data = request.json
        if not data or 'thread_id' not in data or 'message' not in data:
            return jsonify({"error": "Missing thread_id or message"}), 400
            
        thread_id = data['thread_id']
        message = data['message']
        
        success = app_instance.conversation_manager.inject_user_message(
            thread_id,
            message
        )
        
        if success:
            return jsonify({
                "status": "success",
                "message": "Message injected into conversation"
            })
        else:
            return jsonify({
                "error": "Failed to inject message"
            }), 500
            
    except Exception as e:
        logger.error(f"Error injecting message: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/favicon.ico')
def favicon():
    return send_from_directory(os.path.join(app.root_path, 'static'),
                             'favicon.ico', mimetype='image/vnd.microsoft.icon')

def handle_error(e: Exception, context: str = ""):
    """Centralized error handling"""
    logger.error(f"Error in {context}: {e}")
    logger.error(f"Traceback: {traceback.format_exc()}")
    monitor_error(e)
    return jsonify({"error": str(e)}), 500

@app.route('/static/fonts/<path:filename>')
def serve_font(filename):
    return send_from_directory(os.path.join(app.root_path, 'static', 'fonts'), filename)

class ModelWarmer:
    """Handles model warm-up and optimization with optimized token scaling"""
    def __init__(self):
        self._lock = threading.Lock()
        self._is_warmed = False
        self._warm_tokens = 0
        
        # Simplified base prompts
        self.prompts = {
            'simple': "Hi",  # Single token
            'medium': "Write a function",  # Few tokens
            'complex': "Explain binary search"  # Several tokens
        }
        
        # Optimized Fibonacci sequence (half the steps)
        self.token_sequence = self._generate_token_sequence(max_tokens=128)  # Reduced from 256
        logger.info(f"[WARM] Initialized with token sequence: {self.token_sequence}")
    
    def _generate_token_sequence(self, max_tokens: int) -> list[int]:
        """Generate optimized Fibonacci sequence with fewer steps"""
        sequence = [1, 2]  # Start minimal
        while len(sequence) < 4:  # Changed from 8 to 9 steps
            next_val = sequence[-1] + sequence[-2]
            if next_val > max_tokens:
                break
            sequence.append(next_val)
        # This will generate something like [1, 2, 3, 5, 8, 13, 21, 34, 55] instead of stopping at 34
        return sequence
    
    def _get_truncated_prompt(self, prompt: str, target_tokens: int, model: Llama) -> str:
        """Truncate prompt to approximate target token count"""
        tokens = model.tokenize(prompt.encode())
        if len(tokens) <= target_tokens:
            return prompt
        return model.detokenize(tokens[:target_tokens]).decode()
    
    def warm_up_model(self, model: Optional[Llama], num_passes: int = 1) -> bool:  # Reduced passes to 1
        """Warm up model with optimized token scaling"""
        if not model or self._is_warmed:
            return False
            
        logger.info("[WARM] Starting optimized warm-up sequence")
        
        with self._lock:
            try:
                total_time = 0
                
                # Single pass with progressive complexity
                for complexity, base_prompt in self.prompts.items():
                    # Scale up tokens progressively
                    for target_tokens in self.token_sequence:
                        start_time = time.time()
                        
                        # Prepare prompt for target token count
                        prompt = self._get_truncated_prompt(base_prompt, target_tokens, model)
                        
                        logger.info(f"[WARM] Generating {target_tokens} tokens with {complexity} prompt")
                        
                        # Generate with increasing token count
                        _ = model.create_completion(
                            prompt,
                            max_tokens=target_tokens,
                            temperature=0.1,  # Keep low temperature for consistency
                            top_p=0.95,
                            top_k=40,
                            repeat_penalty=1.1,
                            stream=False
                        )
                        
                        # Track metrics
                        self._warm_tokens += target_tokens
                        generation_time = time.time() - start_time
                        total_time += generation_time
                        
                        logger.info(f"[WARM] Generated {target_tokens} tokens in {generation_time:.2f}s")
                        
                        # Force CUDA synchronization
                        if torch.cuda.is_available():
                            torch.cuda.synchronize()
                            
                        # Reduced delay between generations
                        time.sleep(0.05)  # Halved from 0.1
                
                self._is_warmed = True
                avg_time_per_token = total_time / self._warm_tokens if self._warm_tokens > 0 else 0
                
                logger.info(f"[WARM] Model warmed up successfully:")
                logger.info(f"[WARM] - Total tokens: {self._warm_tokens}")
                logger.info(f"[WARM] - Total time: {total_time:.2f}s")
                logger.info(f"[WARM] - Avg time per token: {avg_time_per_token:.4f}s")
                
                # Report GPU memory status
                if torch.cuda.is_available():
                    allocated = torch.cuda.memory_allocated() / 1024**2
                    reserved = torch.cuda.memory_reserved() / 1024**2
                    logger.info(f"[WARM] GPU Memory: {allocated:.1f}MB allocated, {reserved:.1f}MB reserved")
                
                return True
                
            except Exception as e:
                logger.error(f"[WARM] Warm-up failed: {e}")
                logger.error(traceback.format_exc())
                return False

    @property
    def is_warmed(self) -> bool:
        return self._is_warmed

    def reset(self):
        """Reset warm-up state"""
        with self._lock:
            self._is_warmed = False
            self._warm_tokens = 0

# Add model warmer to Application class
class Application:
    def __init__(self):
        if hasattr(self, '_initialized'):
            return
            
        # ... existing init code ...
        
        # Add model warmer
        self.model_warmer = ModelWarmer()
        
        # ... rest of init code ...

# Add this before the ModelManager class
class BaseManager:
    """Base class for managers with common cleanup functionality"""
    def __init__(self):
        self._lock = threading.Lock()
        self._initialized = False
    
    def cleanup(self):
        """Base cleanup method"""
        logger.info(f"Cleaning up {self.__class__.__name__}...")
        with self._lock:
            self._cleanup_impl()
    
    def _cleanup_impl(self):
        """Implement in subclasses"""
        pass

    def __new__(cls, *args, **kwargs):
        """Ensure single instance per manager type"""
        if not hasattr(cls, '_instance'):
            cls._instance = super(BaseManager, cls).__new__(cls)
        return cls._instance

# Then the ModelManager class can inherit from it
class ModelManager(BaseManager):
    def __init__(self):
        if hasattr(self, '_initialized'):
            return
            
        super().__init__()
        self._model_lock = threading.Lock()
        self._current_model = None
        self._cuda_initialized = False
        self._loading = threading.Event()
        self.state = None
        self._initialized = True
        
        # Initialize model paths
        self.models_dir = Path("models").absolute()
        self.model_files = {
            'LM_SMALL': 'Qwen2.5-Coder-14B-Instruct-Q6_K_L.gguf',
            'LM_LARGE': 'QwQ-32B-Preview-Q5_K_L.gguf'
        }
        
        # Load default model (LM_SMALL)
        try:
            logger.info("Loading default model (LM_SMALL)")
            self._loading.set()  # Set loading flag
            self._current_model = self._load_model('LM_SMALL')
            if not self._current_model:
                raise RuntimeError("Failed to load default model")
            logger.info("Default model loaded successfully")
        except Exception as e:
            logger.error(f"Failed to load default model: {e}")
            logger.error(traceback.format_exc())
            raise
        finally:
            self._loading.clear()  # Clear loading flag

    def _load_model(self, model_type: str) -> Optional[Llama]:
        """Load model with warm-up sequence"""
        logger.info(f"\n=== LOADING MODEL [VERBOSE] ===")
        
        # ... existing loading code ...
        
        try:
            # Load model as before
            model = load_with_timeout()  # Your existing loading code
            
            if model:
                # Warm up the model
                logger.info("[MODEL] Starting warm-up sequence")
                if app_instance.model_warmer.warm_up_model(model):
                    logger.info("[MODEL] Warm-up completed successfully")
                else:
                    logger.warning("[MODEL] Warm-up skipped or failed")
                    
            return model
            
        except Exception as e:
            logger.error(f"CRITICAL ERROR in _load_model: {e}")
            logger.error(traceback.format_exc())
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
                torch.cuda.synchronize()
            gc.collect()
            raise

    def switch_model(self, model_type: str) -> Tuple[bool, str]:
        """Switch models with warm-up"""
        # ... existing switch code ...
        
        try:
            # Reset warm-up state before switch
            app_instance.model_warmer.reset()
            
            # Existing switch logic
            success, msg = super().switch_model(model_type)
            
            if success:
                # Warm up new model after switch
                model = self.get_current_model()
                if model and app_instance.model_warmer.warm_up_model(model):
                    msg += " Model warmed up successfully."
                else:
                    msg += " Model warm-up skipped."
                    
            return success, msg
            
        except Exception as e:
            logger.error(f"Model switch failed: {e}")
            return False, f"Failed to switch model: {str(e)}"

if __name__ == '__main__':
    try:
        logger.info("\n=== STARTUP SEQUENCE ===")
        logger.info(f"Current working directory: {os.getcwd()}")
        logger.info(f"Python version: {sys.version}")
        logger.info(f"CUDA available: {torch.cuda.is_available()}")
        if torch.cuda.is_available():
            logger.info(f"CUDA device: {torch.cuda.get_device_name(0)}")
            logger.info(f"CUDA version: {torch.version.cuda}")
        
        # Configure Flask
        app.config['JSON_SORT_KEYS'] = False
        app.config['PROPAGATE_EXCEPTIONS'] = True
        
        logger.info("Starting Flask server on http://localhost:5000")
        app.run(debug=False, port=5000, use_reloader=False)
        
    except KeyboardInterrupt:
        logger.info("Shutdown requested via keyboard interrupt")
        cleanup_handler()
    except Exception as e:
        logger.error(f"Startup error: {e}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        cleanup_handler()
        sys.exit(1)
