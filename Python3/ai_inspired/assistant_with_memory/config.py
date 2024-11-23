import os
import secrets
from pathlib import Path

CHOSEN_MODEL = "Replete-LLM-V2.5-Qwen-14b-Q5_K_S.gguf"

# Base directory
BASE_DIR = Path(__file__).resolve().parent

# Model settings
MODELS_DIR = os.path.join(BASE_DIR, "models")
MODEL_FILENAME = CHOSEN_MODEL
MODEL_PATH = os.path.join(MODELS_DIR, MODEL_FILENAME)

# Create models directory if it doesn't exist
os.makedirs(MODELS_DIR, exist_ok=True)

# Model configuration
MODEL_TYPE = "llama"
CONTEXT_LENGTH = 8096

# Memory settings
MEMORY_DIR = os.path.join(BASE_DIR, "memory_store")
SQLITE_DB_PATH = os.path.join(MEMORY_DIR, "memory.db")
os.makedirs(MEMORY_DIR, exist_ok=True)

# Flask settings
SECRET_KEY = secrets.token_hex(32)

# Verify model file existence and provide guidance
if not os.path.exists(MODEL_PATH):
    print("="*80)
    print("ERROR: Model file not found!")
    print(f"Expected model path: {MODEL_PATH}")
    print("\nPlease ensure you:")
    print(F"1. Download the model file '{CHOSEN_MODEL}'")
    print(f"2. Place it in the models directory: {MODELS_DIR}")
    print("\nAlternatively, update MODEL_FILENAME in config.py with your model file name")
    print("="*80)