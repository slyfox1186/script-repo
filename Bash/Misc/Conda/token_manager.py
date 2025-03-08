#!/usr/bin/env python3
"""
token_manager.py - Global Token Manager for synchronized model inference

This module provides a global threading.Lock instance to ensure that only one 
model inference is executed at a time. This is critical to avoid GPU memory 
overload (CUDA OOM errors) when running large LLMs.

Usage:
    Import this module in your scripts:
        from token_manager import lock

If run directly, it will print a help message.

References:
  :contentReference[oaicite:0]{index=0} (Thread-safe singleton pattern inspiration)
"""

import threading

# Create a global lock for synchronizing inference calls across threads.
lock = threading.Lock()

def main():
    print("token_manager.py provides a global threading.Lock instance.")
    print("Usage: Import this module and use 'from token_manager import lock' to wrap model calls.")

if __name__ == '__main__':
    main()
