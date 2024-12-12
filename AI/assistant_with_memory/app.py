from flask import Flask, render_template, request, Response, jsonify, send_from_directory
from chat.chat_manager import ChatManager
import json
import traceback
import asyncio
import signal
import sys
import psutil
import os

app = Flask(__name__)
chat_managers = {}

def cleanup_port(port):
    """Kill any process using the specified port"""
    try:
        for proc in psutil.process_iter(['pid', 'name']):
            try:
                # Get connections separately since it's not a basic attribute
                connections = proc.connections()
                for conn in connections:
                    if hasattr(conn, 'laddr') and hasattr(conn.laddr, 'port'):
                        if conn.laddr.port == port:
                            os.kill(proc.pid, signal.SIGTERM)
                            return True
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue
    except Exception as e:
        print(f"Error cleaning up port: {str(e)}")
    return False

async def cleanup():
    """Cleanup resources before shutdown"""
    try:
        # Cleanup chat managers
        for manager in chat_managers.values():
            if hasattr(manager, 'llm') and manager.llm:
                if hasattr(manager.llm, 'close'):
                    if asyncio.iscoroutinefunction(manager.llm.close):
                        await manager.llm.close()
                    else:
                        manager.llm.close()
    except Exception as e:
        print(f"Error during cleanup: {str(e)}")
        print(traceback.format_exc())

def shutdown_handler(signum, frame):
    """Handle shutdown signals"""
    print("\nShutting down gracefully...")
    asyncio.run(cleanup())
    sys.exit(0)

# Register signal handlers
signal.signal(signal.SIGINT, shutdown_handler)
signal.signal(signal.SIGTERM, shutdown_handler)

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/api/message', methods=['POST'])
def handle_message():
    try:
        if not request.is_json:
            return jsonify({'error': 'Content-Type must be application/json'}), 400
            
        data = request.json
        if not data or 'message' not in data:
            return jsonify({'error': 'Message is required'}), 400
            
        message = data.get('message')
        user_id = request.headers.get('X-User-Id', 'default')

        async def async_generator():
            try:
                # Initialize chat manager if needed
                if user_id not in chat_managers:
                    chat_managers[user_id] = ChatManager(user_id)
                
                # Send start event
                yield 'data: {"type": "start"}\n\n'
                
                # Stream the chat response
                async for token in chat_managers[user_id].chat(message):
                    if token:
                        # Format as SSE event
                        event_data = json.dumps({
                            "type": "token",
                            "token": token
                        })
                        yield f'data: {event_data}\n\n'
                
                # Send completion event
                yield 'data: {"type": "done"}\n\n'
                
            except Exception as e:
                error_msg = json.dumps({
                    "type": "error",
                    "error": str(e)
                })
                yield f'data: {error_msg}\n\n'
                print(f"Error in message generation: {str(e)}")
                print(f"Traceback: {traceback.format_exc()}")

        def generate():
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                return loop.run_until_complete(stream_async_generator(async_generator()))
            finally:
                loop.close()

        async def stream_async_generator(generator):
            result = []
            async for item in generator:
                result.append(item)
            return result

        return Response(
            generate(),
            mimetype='text/event-stream',
            headers={
                'Cache-Control': 'no-cache',
                'X-Accel-Buffering': 'no',
                'Connection': 'keep-alive',
                'Content-Type': 'text/event-stream',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': '*'
            }
        )

    except Exception as e:
        print(f"Error in handle_message: {str(e)}")
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/static/<path:path>')
def send_static(path):
    return send_from_directory('static', path)

@app.route('/favicon.ico')
def favicon():
    return send_from_directory('static', 'favicon.ico', mimetype='image/vnd.microsoft.icon')

if __name__ == '__main__':
    port = 5000
    retries = 3
    
    while retries > 0:
        try:
            # Try to clean up the port first
            cleanup_port(port)
            app.run(port=port, debug=False)
            break
        except OSError as e:
            if "Address already in use" in str(e):
                print(f"Port {port} is still in use, trying to cleanup...")
                retries -= 1
                if retries == 0:
                    print("Could not start server after multiple attempts")
                    sys.exit(1)
            else:
                raise 
