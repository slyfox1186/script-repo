#!/usr/bin/env python3
"""
client.py - Client Orchestrator for Dual LLM Inference

This script loads a local 14B model (e.g. bartowski/DeepSeek-R1-Distill-Qwen-14B-GGUF) fully into VRAM 
using llama-cpp-python to produce a draft answer, then sends a request to a remote server (running on PC1) 
to obtain a detailed answer from a 32B model. The two answers are then combined.

Usage:
    python3 client.py --model_path /path/to/DeepSeek-R1-Qwen-14B-quantized.gguf 
                      --server_url http://<PC1_IP>:5000/generate
                      [--n_ctx 2048] [--n_gpu_layers -1] [--n_batch 256]
                      [--max_tokens 256] [--temperature 0.7] [--top_p 0.9]
                      [--question "Your question here"]

References:
  :contentReference[oaicite:4]{index=4} (FastAPI usage)  
  :contentReference[oaicite:5]{index=5} (Singleton/thread safety best practices)

clear; python3 server.py --model_path /models/QwQ-32B-Q4_K_L.gguf --host 0.0.0.0 --port 5000
clear; python3 client.py --model_path /models/name.gguf --server_url http://192.168.50.177:5000/generate
"""

import os
import argparse
import sys
import requests
from llama_cpp import Llama
from token_manager import lock

# Global variable for local 14B model.
llm_local = None

def load_local_model(model_path):
    try:
        print("Loading local 14B model from:", model_path)
        model = Llama(
            model_path=model_path,
            n_ctx=6000,
            n_batch=512,
            n_threads=os.cpu_count(),
            main_gpu=0,
            n_gpu_layers=-1,
            flash_attn=True,
            seed=47,
            use_mmap=True,
            use_mlock=True,
            offload_kqv=True,
            verbose=True
        )
        print("Local 14B model loaded successfully.")
        return model
    except Exception as e:
        print(f"Failed to load local model: {e}", file=sys.stderr)
        sys.exit(1)

def get_remote_response(server_url, prompt, max_tokens, temperature, top_p):
    try:
        payload = {
            "prompt": prompt,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "top_p": top_p,
        }
        response = requests.post(server_url, json=payload, timeout=60)
        response.raise_for_status()
        data = response.json()
        return data.get("result", "")
    except Exception as e:
        print(f"Error calling remote server: {e}", file=sys.stderr)
        return ""

def solve_task(question, server_url):
    global llm_local
    # Generate draft answer from local 14B model.
    with lock:
        try:
            draft_output = llm_local(
                question,
                max_tokens=None,
                temperature=0.6,
                top_p=95,
                stream=True,
                echo=False,
                stop=["<｜User｜>", "<｜Assistant｜>"]
            )
            draft_text = draft_output.get("choices", [{}])[0].get("text", "").strip()
        except Exception as e:
            draft_text = f"Error in local model inference: {e}"
    
    print("Draft answer from local 14B model:")
    print(draft_text)
    print("-" * 40)
    
    # Get detailed answer from remote 32B model.
    detailed_text = get_remote_response(server_url, question)
    print("Detailed answer from remote 32B model:")
    print(detailed_text)
    print("-" * 40)
    
    final_answer = f"Draft (14B): {draft_text}\nDetailed (32B): {detailed_text}"
    return final_answer

def parse_args():
    parser = argparse.ArgumentParser(
        description="Client orchestrator for dual LLM inference (local 14B and remote 32B models).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--model_path", type=str, required=True, help="Path to the local 14B model GGUF file.")
    parser.add_argument("--server_url", type=str, required=True, help="URL of the remote server endpoint (e.g., http://<PC1_IP>:5000/generate).")
    parser.add_argument("--n_ctx", type=int, default=2048, help="Context size for the local model.")
    parser.add_argument("--n_gpu_layers", type=int, default=-1, help="Number of GPU layers for the local model (-1 for all).")
    parser.add_argument("--n_batch", type=int, default=256, help="Batch size for the local model.")
    parser.add_argument("--max_tokens", type=int, default=256, help="Max tokens for remote generation.")
    parser.add_argument("--temperature", type=float, default=0.7, help="Sampling temperature.")
    parser.add_argument("--top_p", type=float, default=0.9, help="Top-p sampling parameter.")
    parser.add_argument("--question", type=str, default="", help="Question or prompt to ask the models.")
    return parser.parse_args()

def main():
    global llm_local
    args = parse_args()
    llm_local = load_local_model(args.model_path, args.n_ctx, args.n_gpu_layers, args.n_batch)
    
    question = args.question if args.question else input("Enter your question/prompt: ")
    final_answer = solve_task(question, args.server_url, args.max_tokens, args.temperature, args.top_p)
    print("Final combined answer:")
    print(final_answer)

if __name__ == "__main__":
    main()
