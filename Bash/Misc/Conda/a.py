#!/usr/bin/env python3
# llama_client.py
"""
Wrapper for llama-cpp-python to load and run the OtherModel GGUF model.
Provides a generate() method to output refined responses based on the input prompt.
"""

import os
import sys
from llama_cpp import Llama

class OtherLLM:
    def __init__(self, model_path: str):
        try:
            self.model = Llama(
                model_path=model_path,
                n_ctx=4096,
                n_batch=512,
                n_threads=os.cpu_count(),
                main_gpu=0,
                n_gpu_layers=-1,  # Adjust based on GPU resources
                flash_attn=True,
                use_mmap=True,
                use_mlock=True,
                offload_kqv=True,
                verbose=True
            )
        except Exception as e:
            print(f"Error initializing OtherLLM: {e}")
            sys.exit(1)

    def generate(self, prompt: str, max_tokens: int = 512) -> str:
        try:
            response = self.model(prompt, max_tokens=max_tokens,
                                  stop=["<|Assistant|>", "<|User|>", "<|begin▁of▁sentence▁|>"])
            text = response["choices"][0]["text"]
            return text.strip()
        except Exception as e:
            raise RuntimeError(f"OtherModel generation failed: {e}")


# llama_server.py
#!/usr/bin/env python3
"""
Wrapper for llama-cpp-python to load and run the Qwen_QwQ-32B GGUF model.
Provides a generate() method to output responses based on the input prompt.
"""

import os
import sys
from llama_cpp import Llama

class QwenLLM:
    def __init__(self, model_path: str):
        try:
            self.model = Llama(
                model_path=model_path,
                n_ctx=4096,
                n_batch=512,
                n_threads=os.cpu_count(),
                main_gpu=0,
                n_gpu_layers=-1,  # Adjust based on GPU resources
                flash_attn=True,
                use_mmap=True,
                use_mlock=True,
                offload_kqv=True,
                verbose=True
            )
        except Exception as e:
            print(f"Error initializing QwenLLM: {e}")
            sys.exit(1)

    def generate(self, prompt: str, max_tokens: int = 512) -> str:
        try:
            response = self.model(prompt, max_tokens=max_tokens, stop=["<|im_end|>", "<|im_start|>"])
            text = response["choices"][0]["text"]
            return text.strip()
        except Exception as e:
            raise RuntimeError(f"Model generation failed: {e}")
