#!/usr/bin/env python3
"""
Redis Memory Module for AI Debate System
========================================

This module provides functions to store and retrieve conversation history
using Redis hashes and vectors. It connects to an existing Redis Stack server
and provides persistent memory between debate sessions.

Usage:
    import redis_memory
    
    # Store a message
    redis_memory.store_message(session_id, source, message, turn_number)
    
    # Get conversation history
    history = redis_memory.get_conversation_history(session_id)
    
    # Get the last message from a specific source
    last_message = redis_memory.get_last_message(session_id, source)
"""

import redis
import json
import time
from typing import Dict, List, Optional, Tuple, Any

# Connect to the existing Redis Stack server
# Using default Redis connection parameters
REDIS_HOST = "localhost"
REDIS_PORT = 6379
REDIS_DB = 0
REDIS_PASSWORD = None  # Set this if your Redis server requires authentication

# Session ID for persistent memory
SESSION_ID = "memory_001"

# Redis key prefixes
HASH_PREFIX = "debate:memory:"
VECTOR_PREFIX = "debate:vector:"

# Initialize Redis connection
redis_client = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    db=REDIS_DB,
    password=REDIS_PASSWORD,
    decode_responses=True  # Automatically decode responses to strings
)

def check_connection() -> bool:
    """Check if the Redis connection is working."""
    try:
        return redis_client.ping()
    except redis.ConnectionError:
        print("Error: Could not connect to Redis server")
        return False

def store_message(session_id: str, source: str, message: str, turn_number: int) -> bool:
    """
    Store a message in Redis using hashes.
    
    Args:
        session_id: Unique identifier for the debate session
        source: Source of the message (e.g., "LLM1", "LLM2")
        message: The message content
        turn_number: The turn number in the conversation
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        # Create a unique key for this message
        message_key = f"{source}:{turn_number}"
        
        # Create a hash with message details
        message_data = {
            "source": source,
            "message": message,
            "turn": turn_number,
            "timestamp": time.time()
        }
        
        # Store in Redis hash
        hash_key = f"{HASH_PREFIX}{session_id}"
        redis_client.hset(hash_key, message_key, json.dumps(message_data))
        
        # Make the key persistent (no expiration)
        redis_client.persist(hash_key)
        
        # Update the last turn number for quick access
        redis_client.hset(f"{HASH_PREFIX}meta:{session_id}", f"last_turn_{source}", turn_number)
        
        return True
    except Exception as e:
        print(f"Error storing message in Redis: {e}")
        return False

def get_conversation_history(session_id: str) -> List[Dict[str, Any]]:
    """
    Retrieve the entire conversation history for a session.
    
    Args:
        session_id: Unique identifier for the debate session
        
    Returns:
        List of message dictionaries in chronological order
    """
    try:
        # Get all messages from the hash
        hash_key = f"{HASH_PREFIX}{session_id}"
        all_messages = redis_client.hgetall(hash_key)
        
        # Parse JSON and sort by turn number
        messages = []
        for _, message_json in all_messages.items():
            message_data = json.loads(message_json)
            messages.append(message_data)
        
        # Sort by turn number
        messages.sort(key=lambda x: x["turn"])
        
        return messages
    except Exception as e:
        print(f"Error retrieving conversation history from Redis: {e}")
        return []

def get_last_message(session_id: str, source: str) -> Optional[str]:
    """
    Get the last message from a specific source.
    
    Args:
        session_id: Unique identifier for the debate session
        source: Source of the message (e.g., "LLM1", "LLM2")
        
    Returns:
        The last message content or None if not found
    """
    try:
        # Get the last turn number for this source
        meta_key = f"{HASH_PREFIX}meta:{session_id}"
        last_turn = redis_client.hget(meta_key, f"last_turn_{source}")
        
        if not last_turn:
            return None
            
        # Get the message
        hash_key = f"{HASH_PREFIX}{session_id}"
        message_key = f"{source}:{last_turn}"
        message_json = redis_client.hget(hash_key, message_key)
        
        if not message_json:
            return None
            
        message_data = json.loads(message_json)
        return message_data.get("message")
    except Exception as e:
        print(f"Error retrieving last message from Redis: {e}")
        return None

def get_full_context(session_id: str, topic: str) -> Dict[str, Any]:
    """
    Get the full context of the debate, including topic and all messages.
    
    Args:
        session_id: Unique identifier for the debate session
        topic: The debate topic
        
    Returns:
        Dictionary with topic and messages
    """
    try:
        messages = get_conversation_history(session_id)
        
        # Store the topic if it's not already stored
        redis_client.hset(f"{HASH_PREFIX}meta:{session_id}", "topic", topic)
        
        return {
            "topic": topic,
            "messages": messages
        }
    except Exception as e:
        print(f"Error retrieving full context from Redis: {e}")
        return {"topic": topic, "messages": []}

def clear_session(session_id: str) -> bool:
    """
    Clear all data for a specific session.
    
    Args:
        session_id: Unique identifier for the debate session
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        hash_key = f"{HASH_PREFIX}{session_id}"
        meta_key = f"{HASH_PREFIX}meta:{session_id}"
        
        redis_client.delete(hash_key)
        redis_client.delete(meta_key)
        
        return True
    except Exception as e:
        print(f"Error clearing session from Redis: {e}")
        return False

def format_prompt_with_history(session_id: str, source: str, topic: str, 
                              current_turn: int) -> str:
    """
    Format a prompt with conversation history for the LLM.
    
    Args:
        session_id: Unique identifier for the debate session
        source: Source of the message (e.g., "LLM1", "LLM2")
        topic: The debate topic
        current_turn: The current turn number
        
    Returns:
        Formatted prompt string with conversation history
    """
    try:
        messages = get_conversation_history(session_id)
        
        # Build the prompt
        prompt = f"Debate topic: {topic}.\n\n"
        
        # Add conversation history
        for msg in messages:
            if msg["source"] == "LLM1":
                prompt += f"You said: {msg['message']}\n\n"
            elif msg["source"] == "LLM2":
                prompt += f"The other debater said: {msg['message']}\n\n"
        
        # Add appropriate instruction based on turn
        if current_turn == 0:
            prompt += "State your argument."
        else:
            prompt += "Continue the debate by responding to their points."
            
        return prompt
    except Exception as e:
        print(f"Error formatting prompt with history: {e}")
        # Fallback to basic prompt
        return f"Debate topic: {topic}. State your argument."

# Test connection on module import
if not check_connection():
    print("Warning: Redis connection failed. Memory features will not work.") 
