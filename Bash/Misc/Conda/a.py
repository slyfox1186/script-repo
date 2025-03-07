#!/usr/bin/env python3
"""
Server Script
--------------
This script sets up a Flask server on port 5000 to connect two LLM clients.
It receives messages from one client, saves them to a Redis‑stack‑server for
temporal memory, and forwards the messages to the opposite client.
It also provides a /redis_config endpoint that returns the Redis connection
information so external clients can use the server’s Redis instance.
Usage:
    python server.py --external_client_ip 192.168.50.25 --local_client_ip 192.168.50.177
Optional arguments include the Redis host/port and the server port.
"""

import argparse
import logging
import json
import redis
import requests
from flask import Flask, request, jsonify

# Set up logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

app = Flask(__name__)

# Global variables for client URLs and Redis connection
external_client_url = None  # e.g., "192.168.50.25:5001"
local_client_url = None     # e.g., "192.168.50.177:5001"
redis_client = None
# This variable holds the external (network-accessible) IP for Redis
redis_external_host = None

@app.route('/message', methods=['POST'])
def message():
    """
    Expects JSON payload with keys:
       - sender: "external" or "local"
       - message: The prompt/message text
    Saves the message in Redis and forwards it to the opposite client.
    """
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400

        sender = data.get('sender')
        message_text = data.get('message')
        if not sender or not message_text:
            return jsonify({"error": "Missing sender or message"}), 400

        # Store the message in Redis for temporal memory
        redis_client.rpush("conversation", json.dumps(data))
        logging.info(f"Stored message from '{sender}' in Redis.")

        # Determine the target client based on sender
        if sender == "external":
            target_url = f"http://{local_client_url}/generate"
        elif sender == "local":
            target_url = f"http://{external_client_url}/generate"
        else:
            return jsonify({"error": "Unknown sender value"}), 400

        # Forward the message to the target client
        logging.info(f"Forwarding message from '{sender}' to {target_url}")
        response = requests.post(target_url, json=data, timeout=5)
        if response.status_code != 200:
            return jsonify({"error": "Failed to forward message", "details": response.text}), 500

        return jsonify({"status": "Message forwarded", "response": response.json()})
    except Exception as e:
        logging.exception("Error in /message endpoint")
        return jsonify({"error": str(e)}), 500

@app.route('/memory', methods=['GET'])
def memory():
    """
    Returns the full conversation history stored in Redis.
    """
    try:
        messages = redis_client.lrange("conversation", 0, -1)
        conversation = [json.loads(m.decode()) for m in messages]
        return jsonify({"conversation": conversation})
    except Exception as e:
        logging.exception("Error in /memory endpoint")
        return jsonify({"error": str(e)}), 500

@app.route('/redis_config', methods=['GET'])
def redis_config():
    """
    Returns the Redis connection configuration.
    External clients can use this endpoint to connect to the Redis-stack-server.
    """
    try:
        config = {
            "redis_host": redis_external_host,
            "redis_port": redis_client.connection_pool.connection_kwargs.get("port", 6379)
        }
        return jsonify(config)
    except Exception as e:
        logging.exception("Error in /redis_config endpoint")
        return jsonify({"error": str(e)}), 500

def main():
    parser = argparse.ArgumentParser(
        description="Server to connect two local LLM clients over the network."
    )
    parser.add_argument('--external_client_ip', type=str, required=True,
                        help="IP address of the external client (3080 Ti).")
    parser.add_argument('--local_client_ip', type=str, required=True,
                        help="IP address of the local client (4090 Geforce). This should be the network IP of the machine hosting Redis and this server.")
    parser.add_argument('--redis_host', type=str, default='localhost',
                        help="Hostname for the Redis server (default: localhost).")
    parser.add_argument('--redis_port', type=int, default=6379,
                        help="Port for the Redis server (default: 6379).")
    parser.add_argument('--port', type=int, default=5000,
                        help="Port for the server to run on (default: 5000).")
    args = parser.parse_args()

    global external_client_url, local_client_url, redis_client, redis_external_host
    external_client_url = f"{args.external_client_ip}:5001"
    local_client_url = f"{args.local_client_ip}:5001"
    # The external address for Redis will be the same as the local client's network IP
    redis_external_host = args.local_client_ip

    try:
        redis_client = redis.Redis(host=args.redis_host, port=args.redis_port, db=0)
        redis_client.ping()
        logging.info("Connected to Redis successfully.")
    except Exception as e:
        logging.error("Failed to connect to Redis: " + str(e))
        exit(1)

    logging.info(f"Starting server on port {args.port}...")
    app.run(host='0.0.0.0', port=args.port)

if __name__ == '__main__':
    main()
