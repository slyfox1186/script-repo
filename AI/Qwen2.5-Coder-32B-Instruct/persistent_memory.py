import json
import os
import threading
import torch
from datetime import datetime
from llama_cpp import Llama
from pathlib import Path
from typing import (
    Any,
    Dict,
    List,
    Optional,
    Tuple
)

# Set these according to the amount of VRAM you have available
GPU_LAYERS_CODER = 63
GPU_LAYERS_FAST = 29

class InMemoryStore:
    """Simple in-memory store for semantic memory"""
    def __init__(self):
        self._store: Dict[str, Any] = {}
        self._lock = threading.Lock()
    
    def set(self, key: str, value: Any) -> None:
        with self._lock:
            self._store[key] = value
    
    def get(self, key: str) -> Optional[Any]:
        with self._lock:
            return self._store.get(key)
    
    def clear(self) -> None:
        with self._lock:
            self._store.clear()

class GPUManager:
    def __init__(self):
        # VRAM Configuration (23GB for models)
        self.total_vram = 23 * 1024  # 23,552 MB
        
        # Layer allocation based on actual VRAM usage
        self.qwen_layers = GPU_LAYERS_CODER    # Main model (Qwen 32B)
        self.replete_layers = GPU_LAYERS_FAST  # Memory model (Qwen 1.5B - Can allocate more layers since it's smaller)
        
        print(f"\nGPU Memory Allocation:")
        print(f"Total VRAM for models: {self.total_vram:,}MB")
        print(f"Qwen layers: {self.qwen_layers} (using {self.qwen_layers * 330:,}MB)")
        print(f"Replete layers: {self.replete_layers} (using {self.replete_layers * 110:,}MB)")  # Smaller per-layer size
        print(f"Total GPU Memory Used: {(self.qwen_layers * 330) + (self.replete_layers * 110):,}MB\n")
        
        # Configure VRAM usage
        torch.cuda.set_per_process_memory_fraction(0.95)  # Leave some headroom
        os.environ['MALLOC_TRIM_THRESHOLD_'] = '65536'
        
    def setup_for_main_model(self):
        torch.cuda.empty_cache()
        
    def setup_for_memory_model(self):
        torch.cuda.empty_cache()

class ModelManager:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super(ModelManager, cls).__new__(cls)
                cls._instance._initialize()
            return cls._instance

    def _initialize(self):
        self.gpu_manager = GPUManager()
        
        # Initialize Replete model (7B version)
        self.gpu_manager.setup_for_memory_model()
        self.memory_model = Llama(
            model_path="./models/Qwen2.5-1.5B-Instruct-Q8_0.gguf",
            n_ctx=32768,
            n_batch=512,
            n_threads=os.cpu_count(),
            n_gpu_layers=self.gpu_manager.replete_layers,
            main_gpu=0,
            offload_kqv=False,
            flash_attn=True,
            torch_dtype="auto",
            attn_implementation="flash_attention_2",
            use_mmap=True,
            use_mlock=False,
            seed=-1,
            verbose=True,
            rope_scaling={
                "type": "yarn",
                "factor": 4.0,
                "original_max_position_embeddings": 32768
            }
        )
        
        # Print model info
        print(f"\nReplete Model Info:")
        print(f"Context length: {self.memory_model.context_params.n_ctx}")
        print(f"Model size: 7B parameters")
        
        # Initialize Qwen model
        self.gpu_manager.setup_for_main_model()
        self.main_model = Llama(
            model_path="./models/Qwen2.5-Coder-32B-Instruct-Q5_K_L.gguf",
            n_ctx=32768,
            n_batch=512,
            n_threads=os.cpu_count(),
            n_gpu_layers=self.gpu_manager.qwen_layers,
            main_gpu=0,
            offload_kqv=False,
            flash_attn=True,
            torch_dtype="auto",
            attn_implementation="flash_attention_2",
            use_mmap=True,
            use_mlock=False,
            seed=-1,
            verbose=True,
            rope_scaling={
                "type": "yarn",
                "factor": 4.0,
                "original_max_position_embeddings": 32768
            }
        )
        
        # Print model info
        print(f"\nQwen Model Info:")
        print(f"Context length: {self.main_model.context_params.n_ctx}")
        print(f"Model size: 32B parameters")
        print(f"RoPE scaling: YaRN (factor: 4.0)\n")

    def get_memory_model(self):
        with self._lock:
            self.gpu_manager.setup_for_memory_model()
            return self.memory_model

    def get_main_model(self):
        with self._lock:
            self.gpu_manager.setup_for_main_model()
            return self.main_model

class MemoryStore:
    def __init__(self, 
                 storage_path: str = "conversation_history",
                 max_context_length: int = 32768):
        # Create base storage directory
        self.storage_path = Path(storage_path)
        self.storage_path.mkdir(parents=True, exist_ok=True)
        
        # Define paths for all storage files
        self.tokens_file = self.storage_path / "token_count.json"
        self.code_cache_file = self.storage_path / "code_responses.json"
        
        # Handle migration of old chat history if it exists
        self._migrate_old_chat_history()
        
        # Rest of initialization...
        self.max_context_length = max_context_length
        self.model_manager = ModelManager()
        self.load_token_count()
        self.semantic_store = InMemoryStore()
        
        # Ensure write permissions
        if not os.access(self.storage_path, os.W_OK):
            raise PermissionError(f"No write access to {self.storage_path}")
        
        # Initialize cache
        self.cache_version = "1.0"
        self.code_cache = self._load_code_cache()
        self.similarity_threshold = 0.95

    def _migrate_old_chat_history(self):
        """Migrate old chat_history.json to thread-based system"""
        old_chat_history = Path("chat_history.json")
        if old_chat_history.exists():
            try:
                print("Found old chat_history.json, migrating to thread-based system...")
                with open(old_chat_history, 'r') as f:
                    old_messages = json.load(f)
                
                if isinstance(old_messages, list):
                    # Create default thread file
                    default_thread_file = self._get_thread_file('default')
                    
                    # Don't overwrite existing thread file
                    if not default_thread_file.exists():
                        print("Migrating messages to default thread")
                        with open(default_thread_file, 'w') as f:
                            json.dump(old_messages, f, indent=2)
                        
                        # Create backup of old file
                        backup_file = old_chat_history.with_suffix('.json.bak')
                        import shutil
                        shutil.copy2(old_chat_history, backup_file)
                        
                        # Remove old file only if migration successful
                        old_chat_history.unlink()
                        print("Successfully migrated chat history to thread-based system")
                    else:
                        print("Default thread already exists, skipping migration")
                else:
                    print("Old chat history format not recognized, skipping migration")
                    
            except Exception as e:
                print(f"Error migrating chat history: {e}")
                # Don't delete original file if migration failed
                print("Original chat_history.json preserved")

    def _get_thread_file(self, thread_id: str) -> Path:
        """Get path to thread file with validation"""
        # Sanitize thread_id to prevent directory traversal
        safe_thread_id = "".join(c for c in thread_id if c.isalnum() or c in ('-', '_'))
        if safe_thread_id != thread_id:
            print(f"Warning: Thread ID sanitized from '{thread_id}' to '{safe_thread_id}'")
        return self.storage_path / f"{safe_thread_id}.json"

    def load_token_count(self):
        """Load total token count from persistent storage"""
        if self.tokens_file.exists():
            try:
                with open(self.tokens_file, 'r') as f:
                    data = json.load(f)
                self.total_tokens_used = data.get('total_tokens', 0)
            except Exception as e:
                print(f"Error loading token count: {e}")
                self.total_tokens_used = 0
        else:
            self.total_tokens_used = 0

    def save_token_count(self):
        """Save total token count to persistent storage"""
        try:
            with open(self.tokens_file, 'w') as f:
                json.dump({'total_tokens': self.total_tokens_used}, f)
        except Exception as e:
            print(f"Error saving token count: {e}")

    def _load_thread(self, thread_id: str) -> List[Dict]:
        file_path = self._get_thread_file(thread_id)
        if file_path.exists():
            with open(file_path, 'r') as f:
                return json.load(f)
        return []

    def _save_thread(self, thread_id: str, messages: List[Dict]):
        """Save thread with backup and verification"""
        file_path = self._get_thread_file(thread_id)
        backup_path = file_path.with_suffix('.json.bak')
        
        # Create backup of existing file
        if file_path.exists():
            import shutil
            shutil.copy2(file_path, backup_path)
        
        try:
            # Write to temporary file first
            temp_path = file_path.with_suffix('.json.tmp')
            with open(temp_path, 'w') as f:
                json.dump(messages, f, indent=2)
            
            # Verify the temporary file
            with open(temp_path, 'r') as f:
                verify_data = json.load(f)
            if verify_data != messages:
                raise Exception("Data verification failed")
            
            # Rename temporary file to actual file
            os.replace(temp_path, file_path)
            
            # Remove backup if everything succeeded
            if backup_path.exists():
                backup_path.unlink()
                
        except Exception as e:
            # Restore from backup if available
            if backup_path.exists():
                os.replace(backup_path, file_path)
            print(f"Error saving thread: {e}")
            raise

    def _count_tokens(self, text: str) -> int:
        """Count tokens using the memory model's tokenizer"""
        return len(self.model_manager.memory_model.tokenize(text.encode()))

    def _load_code_cache(self) -> Dict[str, Dict]:
        """Load cached code responses with version checking"""
        if self.code_cache_file.exists():
            try:
                with open(self.code_cache_file, 'r') as f:
                    cache_data = json.load(f)
                
                # Version check
                if cache_data.get('version') != self.cache_version:
                    print("Cache version mismatch, clearing cache")
                    return {'version': self.cache_version, 'responses': {}}
                
                return cache_data.get('responses', {})
            except Exception as e:
                print(f"Error loading code cache: {e}")
                return {'version': self.cache_version, 'responses': {}}
        return {'version': self.cache_version, 'responses': {}}

    def _save_code_cache(self):
        """Save code cache to disk with versioning"""
        try:
            cache_data = {
                'version': self.cache_version,
                'responses': self.code_cache
            }
            with open(self.code_cache_file, 'w') as f:
                json.dump(cache_data, f, indent=2)
        except Exception as e:
            print(f"Error saving code cache: {e}")

    def _normalize_code_query(self, query: str) -> str:
        """Normalize code query for consistent matching"""
        # Remove whitespace and convert to lowercase
        normalized = ' '.join(query.lower().split())
        # Remove common variations in wording
        replacements = {
            'could you ': '',
            'can you ': '',
            'please ': '',
            'help me ': '',
            'i need ': '',
            'write ': '',
            'create ': '',
            'generate ': '',
            'code for ': '',
            'script for ': '',
        }
        for old, new in replacements.items():
            normalized = normalized.replace(old, new)
        return normalized

    def get_cached_code_response(self, query: str) -> Optional[str]:
        """Get cached response for identical code query"""
        normalized_query = self._normalize_code_query(query)
        
        # Check for exact match
        if normalized_query in self.code_cache:
            print(f"Found exact cache match for query: {query}")
            return self.code_cache[normalized_query]['response']
        
        # Check for similar queries
        for cached_query, data in self.code_cache.items():
            if self._queries_are_similar(normalized_query, cached_query):
                print(f"Found similar cache match for query: {query}")
                return data['response']
        
        return None

    def _queries_are_similar(self, query1: str, query2: str) -> bool:
        """Check if two queries are semantically similar with stricter matching"""
        # Remove common prefixes first
        query1 = self._normalize_code_query(query1)
        query2 = self._normalize_code_query(query2)
        
        # Split into words and filter out common words
        common_words = {'the', 'a', 'an', 'in', 'on', 'at', 'to', 'for', 'of', 'with'}
        words1 = {w for w in query1.split() if w not in common_words}
        words2 = {w for w in query2.split() if w not in common_words}
        
        # Calculate Jaccard similarity
        intersection = len(words1.intersection(words2))
        union = len(words1.union(words2))
        
        if not union:
            return False
            
        similarity = intersection / union
        
        # Require higher similarity for longer queries
        length_factor = min(1.0, max(len(words1), len(words2)) / 5)
        required_similarity = self.similarity_threshold - (length_factor * 0.05)
        
        return similarity > required_similarity

    def cache_code_response(self, query: str, response: str):
        """Cache a code response with validation"""
        if '```' not in response:
            return
            
        # Validate code blocks
        code_blocks = [block for block in response.split('```') if block.strip()]
        if not code_blocks:
            return
            
        normalized_query = self._normalize_code_query(query)
        
        # Add metadata for better cache management
        self.code_cache[normalized_query] = {
            'response': response,
            'timestamp': datetime.now().isoformat(),
            'original_query': query,
            'code_block_count': len(code_blocks),
            'cache_version': self.cache_version
        }
        self._save_code_cache()

    def add_message(self, thread_id: str, role: str, content: str):
        """Add message with code response caching"""
        try:
            messages = self._load_thread(thread_id)
            
            # Validate message format
            if not isinstance(messages, list):
                print(f"Invalid messages format for thread {thread_id}, initializing new list")
                messages = []
            
            # Ensure each message has required fields
            messages = [msg for msg in messages if isinstance(msg, dict) and 'content' in msg]
            
            # For assistant responses containing code, cache them
            if role == 'assistant' and '```' in content:
                # Find the corresponding user query
                for i in range(len(messages) - 1, -1, -1):
                    if messages[i].get('role') == 'user':
                        self.cache_code_response(messages[i]['content'], content)
                        break
            
            # Check for duplicate content
            if any(msg.get('content') == content for msg in messages):
                print(f"Duplicate message detected in thread {thread_id}, skipping")
                return
            
            token_count = self._count_tokens(content)
            message = {
                "role": role,
                "content": content,
                "timestamp": datetime.now().isoformat(),
                "tokens": token_count,
                "cumulative_tokens": self.total_tokens_used + token_count
            }
            
            messages.append(message)
            self._save_thread(thread_id, messages)
            self.total_tokens_used += token_count
            self.save_token_count()
            
            self._verify_message_saved(thread_id, message)
            
        except Exception as e:
            print(f"Error adding message to thread {thread_id}: {e}")
            import traceback
            traceback.print_exc()
            raise

    def _verify_message_saved(self, thread_id: str, message: dict):
        """Verify that a message was successfully saved"""
        try:
            messages = self._load_thread(thread_id)
            if not any(
                msg["content"] == message["content"] and 
                msg["timestamp"] == message["timestamp"]
                for msg in messages
            ):
                raise Exception("Message verification failed")
        except Exception as e:
            print(f"Message verification failed: {e}")
            raise

    def get_context(self, thread_id: str, current_query: str) -> Tuple[List[Dict], Dict[str, int]]:
        """Get optimized context for the current conversation"""
        messages = self._load_thread(thread_id)
        if not messages:
            return [], {"prompt_tokens": 0, "total_history_tokens": 0}

        # Remove any incomplete or empty messages
        messages = [msg for msg in messages if msg.get("content", "").strip()]
        
        # Ensure messages are in chronological order
        messages.sort(key=lambda x: x.get("timestamp", ""))
        
        query_tokens = self._count_tokens(current_query)
        available_tokens = self.max_context_length - query_tokens

        # Process messages in chronological order
        unique_messages = []
        seen_content = set()
        
        for msg in messages:
            content = msg["content"]
            if content not in seen_content:
                unique_messages.append(msg)
                seen_content.add(content)
        
        # Keep only recent context
        if len(unique_messages) > 5:
            unique_messages = unique_messages[-5:]

        # Generate conversation summary if context is getting long
        if len(messages) > 10:
            summary = self._generate_summary(messages[:-5])  # Summarize older messages
            if summary:
                unique_messages.insert(0, {
                    "role": "system",
                    "content": f"Previous conversation summary: {summary}",
                    "tokens": self._count_tokens(summary)
                })

        context = []
        total_tokens = 0

        # Add messages while respecting token limit
        for msg in unique_messages:
            msg_tokens = msg["tokens"]
            if total_tokens + msg_tokens > available_tokens:
                break
            
            context.append({
                "role": msg["role"],
                "content": msg["content"]
            })
            total_tokens += msg_tokens

        token_stats = {
            "prompt_tokens": query_tokens + total_tokens,
            "total_history_tokens": total_tokens,
            "available_tokens": available_tokens,
            "total_tokens_used": self.total_tokens_used
        }

        return context, token_stats

    def _generate_summary(self, messages: List[Dict]) -> Optional[str]:
        """Generate a summary of older messages using the memory model"""
        if not messages:
            return None
            
        try:
            # Build prompt for summarization
            summary_prompt = "<|im_start|>system\n"
            summary_prompt += "Summarize the key points from this conversation:\n"
            summary_prompt += "<|im_end|>\n"
            
            for msg in messages:
                summary_prompt += f"<|im_start|>{msg['role']}\n{msg['content']}<|im_end|>\n"
            
            summary_prompt += "<|im_start|>assistant\n"
            
            # Generate summary using memory model
            response = self.model_manager.get_memory_model().create_completion(
                summary_prompt,
                max_tokens=4096,
                temperature=0.1,
                top_p=0.1,
                stop=["<|im_end|>"]
            )
            
            if response and 'choices' in response:
                return response['choices'][0]['text'].strip()
                
        except Exception as e:
            print(f"Error generating summary: {e}")
            return None

    def get_thread_summary(self, thread_id: str) -> Optional[Dict]:
        """Get thread summary with token statistics"""
        messages = self._load_thread(thread_id)
        if not messages:
            return None

        return {
            'thread_id': thread_id,
            'message_count': len(messages),
            'total_tokens': sum(msg["tokens"] for msg in messages),
            'has_summary': any(msg.get("is_summary") for msg in messages),
            'last_updated': messages[-1]["timestamp"]
        }

    def get_token_stats(self, thread_id: str) -> Dict[str, int]:
        """Get token usage statistics for thread"""
        messages = self._load_thread(thread_id)
        if not messages:
            return {
                "total_tokens": 0,
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "messages": 0
            }

        prompt_tokens = sum(
            msg["tokens"] for msg in messages 
            if msg["role"] == "user"
        )
        completion_tokens = sum(
            msg["tokens"] for msg in messages 
            if msg["role"] == "assistant"
        )

        return {
            "total_tokens": prompt_tokens + completion_tokens,
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "messages": len(messages),
            "thread_id": thread_id
        }

    def clear_all(self):
        """Clear all conversation threads and reset state"""
        try:
            print("\n=== Clearing All Conversations ===")
            files_before = list(self.storage_path.glob("*.json"))
            print(f"Files before clearing: {[f.name for f in files_before]}")
            
            if self.storage_path.exists():
                for file in self.storage_path.glob("*.json"):
                    try:
                        print(f"Attempting to delete: {file}")
                        file.unlink()
                        print(f"Successfully deleted: {file}")
                    except Exception as e:
                        print(f"Error deleting {file}: {e}")
            
            # Clear semantic memory
            self.semantic_store.clear()
            print("Cleared semantic memory store")
            
            # Reset internal state
            self.total_tokens_used = 0
            print("Reset token counter")
            
            # Force garbage collection
            import gc
            gc.collect()
            print("Ran garbage collection")
            
            # Clear GPU cache
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
                print("Cleared GPU cache")
            
            # Verify deletion
            files_after = list(self.storage_path.glob("*.json"))
            print(f"Files remaining after clearing: {[f.name for f in files_after]}")
            
            success = len(files_after) == 0
            print(f"Clear operation {'successful' if success else 'failed'}")
            return success
            
        except Exception as e:
            print(f"Error in clear_all: {e}")
            return False
