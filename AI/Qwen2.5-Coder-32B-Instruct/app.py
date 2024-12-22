#!/usr/bin/env python3

from flask import Flask, render_template, request, jsonify, Response, session
from datetime import datetime
import uuid
import re
import json
from functools import partial
import markdown
from threading import Lock
from llama_cpp import Llama
import tiktoken
import redis
import os
import gc

app = Flask(__name__)
# Generate random secret key for session management
app.secret_key = uuid.uuid4().hex
# Configure session cookie
app.config.update(
    SESSION_COOKIE_SECURE=True,
    SESSION_COOKIE_SAMESITE='None',
    SESSION_COOKIE_HTTPONLY=True
)

# Initialize Redis client
redis_client = redis.Redis(
    host='localhost',
    port=6379,
    db=0,
    decode_responses=True,  # Automatically decode responses to str
    socket_timeout=5  # 5 second timeout
)

# Check Redis connection at startup
try:
    redis_client.ping()
    print("✅ Redis connection successful")
    info = redis_client.info()
    print(f"Redis Version: {info['redis_version']}")
    print(f"Memory Used: {info['used_memory_human']}")
except redis.ConnectionError as e:
    print("❌ Redis connection failed! Make sure Redis server is running:")
    print("   1. Install Redis: sudo apt-get install redis-server")
    print("   2. Start Redis: sudo service redis start")
    print("   3. Check status: sudo service redis status")
    print(f"Error: {str(e)}")
    # Don't exit, let the app run with degraded functionality
    pass

# Global lock for model inference
model_lock = Lock()

# Initialize tokenizer
tokenizer = tiktoken.get_encoding("cl100k_base")  # GPT-4 encoding
MAX_CONTEXT_TOKENS = 32768  # Maximum context window
MAX_RESPONSE_TOKENS = 4096  # Maximum response length
CONVERSATION_TTL = 86400  # 24 hours in seconds

def count_tokens(text: str) -> int:
    """Count the number of tokens in a text string."""
    return len(tokenizer.encode(text))

def trim_conversation_to_fit(conversation_history: str, system_prompt: str, current_message: str) -> str:
    """Trim conversation history to fit within token limits."""
    system_tokens = count_tokens(system_prompt)
    message_tokens = count_tokens(current_message)
    max_history_tokens = MAX_CONTEXT_TOKENS - system_tokens - message_tokens - MAX_RESPONSE_TOKENS
    
    if max_history_tokens <= 0:
        return ""
    
    # Split history into pairs and count tokens
    pairs = conversation_history.split("<|im_start|>")
    pairs = [p for p in pairs if p.strip()]  # Remove empty strings
    
    # Count tokens for each pair from newest to oldest
    total_tokens = 0
    included_pairs = []
    
    for pair in reversed(pairs):
        pair_tokens = count_tokens(f"<|im_start|>{pair}")
        if total_tokens + pair_tokens <= max_history_tokens:
            total_tokens += pair_tokens
            included_pairs.insert(0, pair)
        else:
            break
    
    return "<|im_start|>".join(included_pairs) if included_pairs else ""

# Initialize the Qwen model
model_path = "./models/Qwen2.5-Coder-32B-Instruct-Q5_K_S.gguf"
if not os.path.exists(model_path):
    raise FileNotFoundError(f"Model not found at {model_path}")

llm = Llama(
    model_path=model_path,
    n_ctx=32768,  # Context window
    n_threads=os.cpu_count(),  # Adjust based on your CPU
    n_gpu_layers=-1,  # Use all GPU layers
    n_batch=512,     # Increase batch size for GPU performance
    use_mmap=True,
    use_mlock=False,
    offload_kqv=False,
    main_gpu=0,
    verbose=True
)

def process_code_blocks(text):
    """Process code blocks with language detection"""
    result = []
    in_code_block = False
    code_content = []
    current_language = ''
    
    lines = text.split('\n')
    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        
        # Check for code block start
        if not in_code_block and line.startswith('```'):
            # Extract language if specified
            current_language = line[3:].strip()
            # If no language specified, use 'plaintext'
            if not current_language:
                current_language = 'plaintext'
            in_code_block = True
            code_content = []
            i += 1  # Skip the opening ``` line
            continue
            
        # Check for code block end
        elif in_code_block and line.strip() == '```':
            in_code_block = False
            code = '\n'.join(code_content)
            # Only wrap in pre/code tags if not already wrapped
            if not code.startswith('<pre><code'):
                result.append(f'<pre><code class="language-{current_language} hljs" data-highlighted="yes">{code}</code></pre>')
            else:
                result.append(code)
        # Handle content inside code block
        elif in_code_block:
            code_content.append(line)
        # Handle regular text
        else:
            result.append(line)
        i += 1
    
    # Handle unclosed code block
    if in_code_block:
        code = '\n'.join(code_content)
        if not code.startswith('<pre><code'):
            result.append(f'<pre><code class="language-{current_language} hljs" data-highlighted="yes">{code}</code></pre>')
        else:
            result.append(code)
    
    return '\n'.join(result)

def process_markdown(text):
    """Process markdown including code blocks"""
    # First handle code blocks
    text = process_code_blocks(text)
    # Then process remaining markdown, excluding already processed code blocks
    html = markdown.markdown(
        text,
        extensions=['fenced_code', 'tables'],
        extension_configs={
            'fenced_code': {
                'preserve_html': True  # Preserve existing HTML code blocks
            }
        }
    )
    return html

def cleanup_memory():
    """Force garbage collection and CUDA memory cleanup"""
    gc.collect()

def get_conversation(user_id: str) -> list:
    """Get conversation history from Redis."""
    try:
        data = redis_client.get(f"chat:{user_id}")
        if data:
            parsed_data = json.loads(data)
            print(f"\n🔍 Redis GET: chat:{user_id}")
            print("├── Status: Found")
            print(f"├── Messages: {len(parsed_data)}")
            for i, msg in enumerate(parsed_data, 1):
                preview = msg['content'][:100] + '...' if len(msg['content']) > 100 else msg['content']
                print(f"├── [{i}] {msg['role']}: {preview}")
            print("└── End of conversation")
            return parsed_data
        else:
            print(f"\n🔍 Redis GET: chat:{user_id} -> Not Found (New Conversation)")
            return []
    except (redis.RedisError, json.JSONDecodeError) as e:
        print(f"\n⚠️ Redis error, using empty conversation: {e}")
        return []

def save_conversation(user_id: str, messages: list) -> bool:
    """Save conversation history to Redis with TTL."""
    try:
        redis_client.setex(
            f"chat:{user_id}",
            CONVERSATION_TTL,
            json.dumps(messages)
        )
        print(f"\n💾 Redis SETEX: chat:{user_id}")
        print("├── Status: Saved")
        print(f"├── Messages: {len(messages)}")
        print(f"├── TTL: {CONVERSATION_TTL}s")
        for i, msg in enumerate(messages, 1):
            preview = msg['content'][:100] + '...' if len(msg['content']) > 100 else msg['content']
            print(f"├── [{i}] {msg['role']}: {preview}")
        print("└── End of save")
        return True
    except redis.RedisError as e:
        print(f"\n⚠️ Failed to save conversation: {e}")
        return False
    except Exception as e:
        print(f"\n⚠️ Unexpected error saving conversation: {e}")
        return False

def clear_conversation(user_id: str):
    """Clear conversation history from Redis."""
    try:
        result = redis_client.delete(f"chat:{user_id}")
        if result:
            print(f"\n🗑️  Redis DEL: chat:{user_id}")
            print("├── Status: Deleted")
            print("└── Success")
        else:
            print(f"\n🗑️  Redis DEL: chat:{user_id}")
            print("├── Status: Not Found")
            print("└── Nothing to delete")
        return True
    except redis.RedisError as e:
        print(f"\n⚠️ Failed to clear conversation: {e}")
        return False

@app.route('/')
def home():
    if 'user_id' not in session:
        session['user_id'] = uuid.uuid4().hex
    return render_template('index.html')

@app.route('/chat', methods=['POST', 'GET'])
def chat():
    try:
        user_id = session.get('user_id')
        if not user_id:
            return jsonify({'error': 'No session found'}), 401
        
        # Handle POST request for sending messages
        if request.method == 'POST':
            try:
                data = request.json
                if not data:
                    return jsonify({'error': 'No data provided'}), 400
                
                message = data.get('message', '').strip()
                if not message:
                    return jsonify({'error': 'No message provided'}), 400
                
                # Get existing messages or initialize new conversation
                messages = get_conversation(user_id)
                
                # Add user message to history
                messages.append({
                    'role': 'user',
                    'content': message,
                    'timestamp': datetime.now().isoformat()
                })
                
                # Save updated conversation
                if not save_conversation(user_id, messages):
                    return jsonify({'error': 'Failed to save message'}), 500
                
                return jsonify({'status': 'message_received'})
                
            except json.JSONDecodeError:
                return jsonify({'error': 'Invalid JSON data'}), 400
            except Exception as e:
                print(f"Error in POST handler: {str(e)}")
                return jsonify({'error': 'Internal server error'}), 500
        
        # Handle GET request for streaming response
        message = request.args.get('message', '').strip()
        if not message:
            return jsonify({'error': 'No message provided'}), 400
        
        def generate():
            full_response = ""
            response_sent = False
            
            try:
                # Send an immediate acknowledgment
                yield f"data: {json.dumps({'token': ''})}\n\n"
                
                # Verify Redis connection
                try:
                    if not redis_client.ping():
                        yield f"data: {json.dumps({'error': 'Redis connection lost'})}\n\n"
                        return
                    
                    # Monitor Redis memory usage
                    info = redis_client.info('memory')
                    used_memory_peak_perc = float(info.get('used_memory_peak_perc', '0').rstrip('%'))
                    if used_memory_peak_perc > 90.0:  # If memory usage is above 90%
                        print(f"⚠️ High Redis memory usage: {info.get('used_memory_human', 'unknown')}")
                except redis.RedisError as e:
                    print(f"⚠️ Redis error: {str(e)}")
                    yield f"data: {json.dumps({'error': 'Session store unavailable'})}\n\n"
                    return
                
                # Get conversation history
                messages = get_conversation(user_id)
                conversation_history = ""
                
                # Process messages in user-assistant pairs
                for msg in messages:
                    role = msg['role']
                    content = msg['content'].strip()
                    if content:  # Only add non-empty messages
                        conversation_history += f"<|im_start|>{role}\n{content}<|im_end|>\n"
                
                # Build prompt
                system_prompt = """You are a helpful coding assistant. You excel at:
- Writing clean, efficient code
- Explaining complex concepts clearly
- Debugging and problem-solving
- Following best practices and conventions
Please provide clear, concise responses."""
                
                prompt = f"""<|im_start|>system
{system_prompt}<|im_end|>
{conversation_history}<|im_start|>user
{message}<|im_end|>
<|im_start|>assistant
"""
                
                # Check token count
                total_tokens = count_tokens(prompt)
                if total_tokens > MAX_CONTEXT_TOKENS - MAX_RESPONSE_TOKENS:
                    conversation_history = trim_conversation_to_fit(conversation_history, system_prompt, message)
                    prompt = f"""<|im_start|>system
{system_prompt}<|im_end|>
{conversation_history}<|im_start|>user
{message}<|im_end|>
<|im_start|>assistant
"""
                    total_tokens = count_tokens(prompt)
                
                print(f"Prompt tokens: {total_tokens}, Max allowed: {MAX_CONTEXT_TOKENS}")
                
                # Generate response with streaming
                with model_lock:
                    if response_sent:
                        return
                    
                    stream = llm(
                        prompt,
                        max_tokens=min(MAX_RESPONSE_TOKENS, MAX_CONTEXT_TOKENS - total_tokens),
                        stop=["<|im_end|>", "<|im_start|>"],
                        stream=True,
                        temperature=0.7,
                    )
                    
                    # Stream each token
                    for output in stream:
                        if response_sent:
                            break
                            
                        token = output['choices'][0]['text']
                        if token:  # Only process non-empty tokens
                            full_response += token
                            yield f"data: {json.dumps({'token': token})}\n\n"
                            
                            if "<|im_end|>" in token:
                                response_sent = True
                                break
                    
                    # Save complete response if we have content
                    if full_response.strip() and not response_sent:
                        try:
                            # Verify Redis connection again before saving
                            if not redis_client.ping():
                                yield f"data: {json.dumps({'error': 'Failed to save response - Redis connection lost'})}\n\n"
                                return
                                
                            messages = get_conversation(user_id)
                            messages.append({
                                'role': 'assistant',
                                'content': full_response.strip(),
                                'timestamp': datetime.now().isoformat()
                            })
                            
                            if save_conversation(user_id, messages):
                                response_sent = True
                            else:
                                yield f"data: {json.dumps({'error': 'Failed to save response'})}\n\n"
                        except Exception as e:
                            print(f"Error saving response: {str(e)}")
                            yield f"data: {json.dumps({'error': 'Failed to save response'})}\n\n"
                    
                    # Send end marker
                    if not response_sent:
                        yield f"data: {json.dumps({'token': '<|im_end|>'})}\n\n"
            
            except Exception as e:
                print(f"Error in generate: {str(e)}")
                yield f"data: {json.dumps({'error': str(e)})}\n\n"
            finally:
                cleanup_memory()
        
        return Response(
            generate(),
            mimetype='text/event-stream',
            headers={
                'Cache-Control': 'no-cache',
                'Connection': 'keep-alive',
                'Access-Control-Allow-Origin': request.headers.get('Origin', '*'),
                'Access-Control-Allow-Credentials': 'true',
                'X-Accel-Buffering': 'no'
            }
        )
        
    except Exception as e:
        print(f"Unexpected error in chat endpoint: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/history')
def get_history():
    user_id = session.get('user_id')
    if not user_id:
        return jsonify([])
    
    messages = get_conversation(user_id)
    processed_messages = []
    
    for msg in messages:
        processed_content = process_markdown(msg['content'])
        processed_messages.append({
            'role': msg['role'],
            'content': processed_content,
            'timestamp': msg['timestamp']
        })
    
    return jsonify(processed_messages)

@app.route('/clear_history', methods=['POST'])
def clear_history():
    """Clear user's conversation history from Redis."""
    try:
        user_id = session.get('user_id')
        if not user_id:
            return jsonify({'error': 'No session found'}), 400
            
        clear_conversation(user_id)
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/redis_health')
def redis_health():
    """Check Redis server status."""
    try:
        # Try to ping Redis
        if redis_client.ping():
            # Get some stats
            info = redis_client.info()
            stats = {
                'status': 'connected',
                'version': info['redis_version'],
                'connected_clients': info['connected_clients'],
                'used_memory_human': info['used_memory_human'],
                'total_connections_received': info['total_connections_received'],
                'total_commands_processed': info['total_commands_processed']
            }
            return jsonify(stats)
    except redis.RedisError as e:
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500

def generate_streaming_response(conversation_history: str, message: str):
    """Generate streaming response from the model."""
    system_prompt = """You are a helpful coding assistant. You excel at:
- Writing clean, efficient code
- Explaining complex concepts clearly
- Debugging and problem-solving
- Following best practices and conventions
Please provide clear, concise responses."""
    
    # Build the full prompt with conversation history
    prompt = f"""<|im_start|>system
{system_prompt}<|im_end|>
{conversation_history}<|im_start|>user
{message}<|im_end|>
<|im_start|>assistant
"""
    
    # Trim conversation history if needed
    if count_tokens(prompt) > MAX_CONTEXT_TOKENS - MAX_RESPONSE_TOKENS:
        conversation_history = trim_conversation_to_fit(conversation_history, system_prompt, message)
        prompt = f"""<|im_start|>system
{system_prompt}<|im_end|>
{conversation_history}<|im_start|>user
{message}<|im_end|>
<|im_start|>assistant
"""
    
    # Log token usage
    total_tokens = count_tokens(prompt)
    print(f"Prompt tokens: {total_tokens}, Max allowed: {MAX_CONTEXT_TOKENS}")
    
    # Generate response with streaming
    stream = llm(
        prompt,
        max_tokens=min(MAX_RESPONSE_TOKENS, MAX_CONTEXT_TOKENS - total_tokens),
        stop=["<|im_end|>", "<|im_start|>"],
        stream=True,
        temperature=0.7,
    )
    
    # Stream each token from the model
    for output in stream:
        token = output['choices'][0]['text']
        if token:  # Only yield non-empty tokens
            yield token

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False) 
