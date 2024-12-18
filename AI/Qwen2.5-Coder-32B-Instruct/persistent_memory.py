# persistent_memory.py

from typing import (
    Any,
    Callable,
    Dict,
    List,
    Optional,
    ParamSpec,
    Tuple,
    TypeVar,
    Union,
    TYPE_CHECKING,
    Annotated,
    TypedDict
)
from pathlib import Path
import threading
import torch
import gc
import json
import os
import time
import logging
import queue
from copy import deepcopy
from llama_cpp import Llama
from datetime import datetime, timedelta
import torch.cuda.memory
from contextlib import contextmanager
import math
import hashlib
import re
from collections import defaultdict
import atexit
import signal
import sys
import psutil
from operator import add
import traceback
from functools import wraps
import weakref
import uuid
from dataclasses import dataclass, field

# LangGraph imports
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import StateGraph
from langgraph.store.memory import InMemoryStore

# Local imports
from prompts import (
    GPU_LAYERS,
    MAX_CONTEXT_TOKENS_LARGE,
    MAX_CONTEXT_TOKENS_SMALL,
    LM_SMALL_SYSTEM_PROMPT,
    LM_LARGE_SYSTEM_PROMPT,
    MAX_MEMORIES_ALLOWED,
    ROUTER_PROMPT,
    MATH_DETECTOR_PROMPT,
    CONTENT_CLASSIFIER_PROMPT,
    MAX_GENERATION_TOKENS
)

# Setup logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Add a handler if none exists
if not logger.handlers:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s'))
    logger.addHandler(handler)

# Type hints
T = TypeVar('T')
P = ParamSpec('P')

# Add forward references to avoid circular imports
if TYPE_CHECKING:
    from .model_manager import ModelManager
    from .conversation_manager import ConversationManager

class MessageMemory:
    """Enhanced message memory with code context tracking"""
    def __init__(self):
        self._recent_contexts = {}
        self._messages = {}
        self._code_history = {}  # Add code history tracking
        self._max_memories = MAX_MEMORIES_ALLOWED
        self._lock = threading.Lock()
        
    def add_code_context(self, thread_id: str, code_context: Dict):
        """Store code context for a thread"""
        logger.info("\n=== ADD_CODE_CONTEXT: DETAILED DEBUG ===")
        logger.info(f"[CODE_CTX] Thread ID: {thread_id}")
        logger.info(f"[CODE_CTX] Raw input context: {code_context}")
        
        # Input validation
        if not isinstance(code_context, dict):
            logger.error(f"[CODE_CTX] Invalid context type: {type(code_context)}")
            return False
            
        # Check for empty/invalid values
        if not any([code_context.get('file_path'), code_context.get('language'), code_context.get('code')]):
            logger.warning("[CODE_CTX] Context contains only empty values - skipping")
            return False
            
        with self._lock:
            try:
                # Initialize code history
                if thread_id not in self._code_history:
                    logger.info(f"[CODE_CTX] Creating new code history for thread {thread_id}")
                    self._code_history[thread_id] = []
                
                # Deep copy and clean context
                cleaned_context = self._clean_code_context(code_context)
                if not cleaned_context:
                    logger.error("[CODE_CTX] Failed to clean context")
                    return False
                
                # Add to history
                self._code_history[thread_id].append(cleaned_context)
                logger.info(f"[CODE_CTX] Added context successfully")
                logger.info(f"[CODE_CTX] Current history size: {len(self._code_history[thread_id])}")
                logger.info("[CODE_CTX] Added entry details:")
                logger.info(f"[CODE_CTX] - File: '{cleaned_context['file_path']}'")
                logger.info(f"[CODE_CTX] - Language: '{cleaned_context['language']}'")
                logger.info(f"[CODE_CTX] - Code length: {len(cleaned_context['code'])}")
                logger.info(f"[CODE_CTX] - Code preview: {cleaned_context['code'][:100]}...")
                
                # Cleanup if needed
                if len(self._code_history[thread_id]) > self._max_memories:
                    removed = self._code_history[thread_id].pop(0)
                    logger.info(f"[CODE_CTX] Removed oldest entry: {removed.get('timestamp')}")
                
                return True
                
            except Exception as e:
                logger.error(f"[CODE_CTX] Error adding context: {e}")
                logger.error(f"[CODE_CTX] Traceback: {traceback.format_exc()}")
                return False
    
    def _clean_code_context(self, context: Dict) -> Optional[Dict]:
        """Clean and validate code context"""
        logger.info("[CODE_CTX] Cleaning context...")
        
        try:
            # Ensure all required fields exist
            required_fields = {'file_path', 'language', 'code', 'type'}
            if missing := required_fields - set(context.keys()):
                logger.error(f"[CODE_CTX] Missing required fields: {missing}")
                return None
            
            # Clean and validate each field
            cleaned = {
                'file_path': str(context['file_path']).strip(),
                'language': str(context['language']).strip().lower(),
                'code': str(context['code']).strip(),
                'type': str(context['type']).strip(),
                'timestamp': context.get('timestamp', time.time())
            }
            
            # Additional validation
            if not cleaned['code']:
                logger.error("[CODE_CTX] Empty code content")
                return None
                
            if not cleaned['language']:
                logger.warning("[CODE_CTX] Empty language field")
                cleaned['language'] = 'unknown'
                
            if not cleaned['file_path']:
                logger.warning("[CODE_CTX] Empty file path")
                cleaned['file_path'] = 'unknown'
            
            logger.info("[CODE_CTX] Context cleaned successfully")
            logger.info(f"[CODE_CTX] Cleaned context: {cleaned}")
            return cleaned
            
        except Exception as e:
            logger.error(f"[CODE_CTX] Error cleaning context: {e}")
            logger.error(f"[CODE_CTX] Traceback: {traceback.format_exc()}")
            return None
    
    def get_code_history(self, thread_id: str, limit: int = 5) -> List[Dict]:
        """Get recent code context history"""
        logger.info("\n=== GET_CODE_HISTORY: DETAILED ENTRY ===")
        logger.info(f"[CODE_HIST] Thread ID: {thread_id}")
        logger.info(f"[CODE_HIST] Requested limit: {limit}")
        
        with self._lock:
            history = self._code_history.get(thread_id, [])
            logger.info(f"[CODE_HIST] Found {len(history)} total entries")
            
            if not history:
                logger.info("[CODE_HIST] No history found for thread")
                return []
            
            # Sort by timestamp and limit
            sorted_history = sorted(history, key=lambda x: x['timestamp'], reverse=True)[:limit]
            logger.info(f"[CODE_HIST] Returning {len(sorted_history)} most recent entries")
            
            # Log detailed entry information
            for idx, entry in enumerate(sorted_history):
                logger.info(f"[CODE_HIST] Entry {idx + 1} details:")
                logger.info(f"[CODE_HIST] - Timestamp: {entry.get('timestamp')}")
                logger.info(f"[CODE_HIST] - File: {entry.get('file_path', 'unknown')}")
                logger.info(f"[CODE_HIST] - Language: {entry.get('language', 'unknown')}")
                logger.info(f"[CODE_HIST] - Code length: {len(entry.get('code', ''))}")
                logger.info(f"[CODE_HIST] - Code preview: {entry.get('code', '')[:100]}...")
            
            # Return a deep copy to prevent modifications
            return deepcopy(sorted_history)

    def clear_all(self) -> bool:
        """Clear all memory data"""
        logger.info("[MEMORY] Clearing all memory data")
        try:
            with self._lock:
                self._recent_contexts.clear()
                self._messages.clear()
                self._code_history.clear()
            logger.info("[MEMORY] Memory cleared successfully")
            return True
        except Exception as e:
            logger.error(f"[MEMORY] Error clearing memory: {e}")
            return False

    def _get_thread_history(self, thread_id: str) -> str:
        """Get conversation history with proper formatting"""
        logger.info("\n=== MESSAGE_MEMORY_HISTORY [EXTREME VERBOSE] ===")
        logger.info(f"[MEM_HIST] Thread ID: {thread_id}")
        logger.info(f"[MEM_HIST] Recent contexts: {self._recent_contexts}")
        logger.info(f"[MEM_HIST] Messages structure: {type(self._messages)}")
        
        try:
            with self._lock:
                messages = self._messages.get(thread_id, [])
                logger.info(f"[MEM_HIST] Raw messages: {messages}")
                
                formatted = []
                for msg in messages:
                    logger.info(f"[MEM_HIST] Processing message: {msg}")
                    if isinstance(msg, dict):
                        role = msg.get('role', 'user')
                        content = msg.get('content', '').strip()
                        formatted.append(f"<rewritten_message><rewritten_role>{role}</rewritten_role>\n{content}</rewritten_message>")
                        logger.info(f"[MEM_HIST] Formatted message: {formatted[-1]}")
                
                result = "\n".join(formatted)
                logger.info(f"[MEM_HIST] Final formatted history: {result}")
                return result
                
        except Exception as e:
            logger.error(f"[MEM_HIST] Error: {e}")
            logger.error(f"[MEM_HIST] Error type: {type(e)}")
            logger.error(f"[MEM_HIST] Error args: {e.args}")
            logger.error(f"[MEM_HIST] Traceback: {traceback.format_exc()}")
            return ""

@dataclass
class ModelConfig:
    """Model configuration settings"""
    n_gpu_layers: int
    n_ctx: int
    n_gpu_layers: int
    n_batch: int
    torch_dtype: str = "auto"
    offload_kqv: bool = False
    use_mmap: bool = True
    use_mlock: bool = True
    verbose: bool = True
    n_threads: int = os.cpu_count()

@dataclass
class ThreadStats:
    active: int = 0
    completed: int = 0
    errors: int = 0
    last_error: str = ''
    last_activity: float = field(default_factory=time.time)

class ThreadSafeCounter:
    def __init__(self):
        self._lock = threading.Lock()
        self._count = 0
    
    def increment(self) -> int:
        with self._lock:
            self._count += 1
            return self._count
    
    def decrement(self) -> int:
        with self._lock:
            self._count = max(0, self._count - 1)
            return self._count

def rate_limit(calls: int, period: float):
    def decorator(func: Callable[P, T]) -> Callable[P, T]:
        last_reset = time.time()
        calls_made = ThreadSafeCounter()
        lock = threading.Lock()
        
        @wraps(func)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> T:
            nonlocal last_reset
            with lock:
                now = time.time()
                if now - last_reset > period:
                    calls_made._count = 0
                    last_reset = now
                if calls_made._count >= calls:
                    sleep_time = period - (now - last_reset)
                    if sleep_time > 0:
                        time.sleep(sleep_time)
                    calls_made._count = 0
                    last_reset = time.time()
                calls_made.increment()
            return func(*args, **kwargs)
        return wrapper
    return decorator

class PersistentState(TypedDict):
    """Strongly typed state definition"""
    messages: list[dict]
    metadata: dict
    context: Annotated[list[str], add]
    last_modified: str

class UnifiedState:
    """Single source of truth for application state"""
    def __init__(self, storage_path: Path):
        self._storage_path = storage_path
        self._lock = threading.Lock()
        
        # Initialize state
        self._state = {
            'messages': {},  # thread_id -> List[Message]
            'metadata': {
                'created_at': datetime.now().isoformat(),
                'version': '1.0'
            },
            'last_modified': datetime.now().isoformat()
        }
        
        # Initialize disk manager
        self.disk_manager = DiskManager(storage_path)
        
        # Load existing state if available
        try:
            loaded_state = self.disk_manager.load_state()
            if loaded_state:
                self._state.update(loaded_state)
        except Exception as e:
            logger.error(f"[STATE] Error loading state: {e}")
            logger.error(traceback.format_exc())
        
        # Initialize components
        self.model_manager = None
        self.conversation_manager = None
        logger.info("[STATE] UnifiedState initialized")

    @property
    def storage_path(self) -> Path:
        """Get storage path"""
        return self._storage_path

    def add_message(self, thread_id: str, message: Dict) -> bool:
        """Add message to state with proper locking"""
        with self._lock:
            try:
                # Initialize thread if needed
                if thread_id not in self._state['messages']:
                    self._state['messages'][thread_id] = []
                
                # Add message
                self._state['messages'][thread_id].append(message)
                self._state['last_modified'] = datetime.now().isoformat()
                
                # Persist state
                return self._persist_state()
            except Exception as e:
                logger.error(f"[STATE] Error adding message: {e}")
                logger.error(traceback.format_exc())
                return False

    def get_thread_history(self, thread_id: str) -> List[Dict]:
        """Get thread history from state"""
        with self._lock:
            return deepcopy(self._state['messages'].get(thread_id, []))

    def _persist_state(self) -> bool:
        """Persist state to disk"""
        try:
            return self.disk_manager.save_state(self._state)
        except Exception as e:
            logger.error(f"[STATE] Error persisting state: {e}")
            logger.error(traceback.format_exc())
            return False

    def clear_thread(self, thread_id: str) -> bool:
        """Clear thread history"""
        with self._lock:
            try:
                if thread_id in self._state['messages']:
                    self._state['messages'][thread_id] = []
                    self._state['last_modified'] = datetime.now().isoformat()
                    return self._persist_state()
                return True
            except Exception as e:
                logger.error(f"[STATE] Error clearing thread: {e}")
                logger.error(traceback.format_exc())
                return False

    def clear_all(self) -> bool:
        """Clear all state"""
        with self._lock:
            try:
                self._state['messages'] = {}
                self._state['last_modified'] = datetime.now().isoformat()
                return self._persist_state()
            except Exception as e:
                logger.error(f"[STATE] Error clearing state: {e}")
                logger.error(traceback.format_exc())
                return False

    def set_memory(self, memory: 'MessageMemory'):
        """Set the memory component"""
        logger.info("[STATE] Setting memory component")
        self.memory = memory

    def set_model_manager(self, model_manager: 'ModelManager'):
        """Set the model manager component"""
        logger.info("[STATE] Setting model manager component")
        self.model_manager = model_manager

    def set_conversation_manager(self, conversation_manager: 'ConversationManager'):
        """Set the conversation manager component"""
        logger.info("[STATE] Setting conversation manager component")
        self.conversation_manager = conversation_manager

    def verify_initialization(self):
        """Verify all required components are initialized"""
        logger.info("[STATE] Verifying component initialization")
        if not all([self.memory, self.model_manager, self.conversation_manager]):
            missing = []
            if not self.memory:
                missing.append("memory")
            if not self.model_manager:
                missing.append("model_manager")
            if not self.conversation_manager:
                missing.append("conversation_manager")
            raise RuntimeError(f"Missing required components: {', '.join(missing)}")
        logger.info("[STATE] All components verified")

    def save_conversations(self, conversations: Dict, history: Dict):
        """Save conversations with disk persistence"""
        logger.info("\n=== SAVE_CONVERSATIONS [EXTREME VERBOSE] ===")
        logger.info(f"[STATE_SAVE] Input conversations type: {type(conversations)}")
        logger.info(f"[STATE_SAVE] Input history type: {type(history)}")
        logger.info(f"[STATE_SAVE] Current state type: {type(self._state)}")
        
        with self._lock:
            try:
                logger.info("[STATE_SAVE] Conversations data:")
                for thread_id, conv in conversations.items():
                    logger.info(f"[STATE_SAVE] Thread {thread_id}:")
                    logger.info(f"[STATE_SAVE] - Messages: {conv.get('messages', [])}")
                    logger.info(f"[STATE_SAVE] - Metadata: {conv.get('metadata', {})}")
                
                logger.info("[STATE_SAVE] History data:")
                for thread_id, msgs in history.items():
                    logger.info(f"[STATE_SAVE] Thread {thread_id} messages:")
                    for msg in msgs:
                        logger.info(f"[STATE_SAVE] - Message: {msg}")
                
                self._state['conversations'] = deepcopy(conversations)
                self._state['conversation_history'] = deepcopy(history)
                self._state['last_modified'] = datetime.now().isoformat()
                
                success = self.disk_manager.save_state(self._state)
                logger.info(f"[STATE_SAVE] Save result: {success}")
                
                return success
                
            except Exception as e:
                logger.error(f"[STATE_SAVE] Error: {e}")
                logger.error(f"[STATE_SAVE] Error type: {type(e)}")
                logger.error(f"[STATE_SAVE] Error args: {e.args}")
                logger.error(f"[STATE_SAVE] Traceback: {traceback.format_exc()}")
                return False

    def load_conversations(self) -> Tuple[Dict, Dict]:
        """Load conversations from disk"""
        logger.info("\n=== LOAD_CONVERSATIONS: EXTREME VERBOSE ===")
        logger.info(f"[LOAD_CONV] Current state: {self._state}")
        logger.info(f"[LOAD_CONV] Lock state: {self._lock}")
        
        try:
            # Load fresh state from disk
            logger.info("[LOAD_CONV] Loading state from disk...")
            state = self.disk_manager.load_state()
            logger.info(f"[LOAD_CONV] Loaded state: {state}")
            
            # Update internal state
            logger.info("[LOAD_CONV] Updating internal state...")
            with self._lock:
                self._state = state
                conversations = deepcopy(state.get('conversations', {}))
                history = deepcopy(state.get('conversation_history', {}))
            
            logger.info(f"[LOAD_CONV] Loaded conversations: {conversations}")
            logger.info(f"[LOAD_CONV] Loaded history: {history}")
            return conversations, history
            
        except Exception as e:
            logger.error(f"[LOAD_CONV] CRITICAL ERROR: {e}")
            logger.error(f"[LOAD_CONV] Error type: {type(e)}")
            logger.error(f"[LOAD_CONV] Error args: {e.args}")
            logger.error(f"[LOAD_CONV] Traceback: {traceback.format_exc()}")
            logger.error(f"[LOAD_CONV] State dump: {vars(self)}")
            return {}, {}

    def build_context(self, thread_id: str, message: str) -> str:
        """Build context with proper prompt formatting"""
        try:
            # Get system prompt
            system_prompt = self._get_system_prompt()
            
            # Build context with proper tags
            context = f"<|im_start|>system\n{system_prompt}<|im_end|>\n"  # Single newline
            
            # Get history
            history = self._get_thread_history(thread_id)
            if history:
                context += f"{history}\n"  # Single newline
            
            # Add current message
            context += f"<|im_start|>user\n{message}<|im_end|>\n"  # Single newline
            context += "<|im_start|>assistant\n"  # No newline after assistant tag
            
            return context
            
        except Exception as e:
            logger.error(f"[CTX_BUILD] Error: {e}")
            return f"<|im_start|>system\n{self._get_system_prompt()}<|im_end|>\n<|im_start|>user\n{message}<|im_end|>\n<|im_start|>assistant\n"

    def save_memory(self, user_id: str, memory: Dict):
        """Save long-term memory for a user"""
        namespace = (user_id, "memories") 
        self.store.put(namespace, str(uuid.uuid4()), memory)

    def get_memories(self, user_id: str) -> List[Dict]:
        """Get all memories for a user"""
        namespace = (user_id, "memories")
        return self.store.search(namespace)

class DiskManager:
    """Manages disk operations for conversation persistence and prompt injection"""
    def __init__(self, storage_path: Path):
        # If storage_path points to a file, use its parent directory
        if storage_path.suffix:  # If path has an extension (is a file)
            self.storage_path = storage_path.parent
            self.conversation_file = storage_path
        else:  # If path is a directory
            self.storage_path = storage_path
            self.conversation_file = storage_path / "unified_state.json"
            
        # Create directory if it doesn't exist
        self.storage_path.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        
        logger.info(f"[DISK] Initialized with storage path: {self.storage_path}")
        logger.info(f"[DISK] Using conversation file: {self.conversation_file}")

    def save_state(self, state: Dict) -> bool:
        """Save state to disk with proper locking"""
        logger.info("\n=== DISK_SAVE [EXTREME VERBOSE] ===")
        logger.info(f"[DISK] State type: {type(state)}")
        logger.info(f"[DISK] State keys: {state.keys()}")
        logger.info(f"[DISK] Storage path: {self.storage_path}")
        logger.info(f"[DISK] Conversation file: {self.conversation_file}")
        
        with self._lock:
            try:
                # Create backup
                if self.conversation_file.exists():
                    backup_path = self.storage_path / f"unified_state.backup.{int(time.time())}.json"
                    logger.info(f"[DISK] Creating backup at: {backup_path}")
                    self.conversation_file.rename(backup_path)
                
                # Save new state
                logger.info("[DISK] Writing state to disk...")
                logger.info(f"[DISK] Conversations: {state.get('conversations', {})}")
                logger.info(f"[DISK] History: {state.get('conversation_history', {})}")
                
                with open(self.conversation_file, 'w') as f:
                    json.dump(state, f, indent=2, default=str)
                
                logger.info("[DISK] State saved successfully")
                return True
                
            except Exception as e:
                logger.error(f"[DISK] Save error: {e}")
                logger.error(f"[DISK] Error type: {type(e)}")
                logger.error(f"[DISK] Error args: {e.args}")
                logger.error(f"[DISK] Traceback: {traceback.format_exc()}")
                return False

    def load_state(self) -> Dict:
        """Load state from disk with fallback to defaults"""
        logger.info("\n=== LOAD_STATE: EXTREME VERBOSE ===")
        logger.info(f"[DISK_LOAD] Loading from {self.conversation_file}")
        logger.info(f"[DISK_LOAD] File exists: {self.conversation_file.exists()}")
        
        try:
            if self.conversation_file.exists():
                logger.info("[DISK_LOAD] Reading existing state file...")
                with open(self.conversation_file, 'r') as f:
                    state = json.load(f)
                logger.info(f"[DISK_LOAD] Loaded state: {state}")
                return state
            
            # Create default state if file doesn't exist
            logger.info("[DISK_LOAD] Creating default state...")
            default_state = {
                'version': '1.0',
                'created_at': datetime.now().isoformat(),
                'last_modified': datetime.now().isoformat(),
                'conversations': {},
                'conversation_history': {},
                'settings': {
                    'max_context_tokens_small': MAX_CONTEXT_TOKENS_SMALL,
                    'max_context_tokens_large': MAX_CONTEXT_TOKENS_LARGE,
                    'max_memories': MAX_MEMORIES_ALLOWED
                }
            }
            logger.info(f"[DISK_LOAD] Default state created: {default_state}")
            self.save_state(default_state)
            return default_state
            
        except Exception as e:
            logger.error(f"[DISK_LOAD] CRITICAL ERROR: {e}")
            logger.error(f"[DISK_LOAD] Error type: {type(e)}")
            logger.error(f"[DISK_LOAD] Error args: {e.args}")
            logger.error(f"[DISK_LOAD] Traceback: {traceback.format_exc()}")
            return self._create_default_state()

    def inject_context(self, messages: List[Dict], system_prompt: str) -> str:
        """Inject conversation history into system prompt"""
        logger.info("[DISK] Injecting conversation context")
        
        try:
            # Format conversation history
            history = []
            for msg in messages:
                role = msg.get('role', 'user')
                content = msg.get('content', '').strip()
                history.append(f"<rewritten_message><rewritten_role>{role}</rewritten_role>\n{content}</rewritten_message>")
            
            # Combine system prompt with history
            context = f"{system_prompt}\n\n"
            if history:
                context += "Previous conversation:\n" + "\n".join(history) + "\n\n"
            
            logger.info(f"[DISK] Created context with {len(history)} messages")
            return context
            
        except Exception as e:
            logger.error(f"[DISK] Error injecting context: {e}")
            logger.error(traceback.format_exc())
            return system_prompt

    def get_recent_code_context(self, thread_id: str, limit: int = 3) -> str:
        """Get recent code context for a thread"""
        logger.info(f"[DISK] Getting code context for thread {thread_id}")
        
        try:
            state = self.load_state()
            history = state.get('conversation_history', {}).get(thread_id, [])
            
            # Extract code blocks from history
            code_blocks = []
            for msg in reversed(history):
                content = msg.get('content', '')
                # Find code blocks with ```language:path/to/file format
                matches = re.finditer(r'```(\w+):([^\n]+)\n(.*?)```', content, re.DOTALL)
                for match in matches:
                    lang, path, code = match.groups()
                    code_blocks.append(f"File: {path}\n```{lang}\n{code.strip()}\n```\n")
                if len(code_blocks) >= limit:
                    break
            
            if code_blocks:
                context = "Recent code context:\n" + "\n".join(code_blocks)
                logger.info(f"[DISK] Found {len(code_blocks)} code blocks")
                return context
            return ""
            
        except Exception as e:
            logger.error(f"[DISK] Error getting code context: {e}")
            logger.error(traceback.format_exc())
            return ""

class BaseManager:
    """Base class for managers with common cleanup functionality"""
    def __init__(self):
        self._lock = threading.Lock()
    
    def cleanup(self):
        """Base cleanup method"""
        logger.info(f"Cleaning up {self.__class__.__name__}...")
        with self._lock:
            self._cleanup_impl()
    
    def _cleanup_impl(self):
        """Implement in subclasses"""
        pass

class ModelManager(BaseManager):
    """Manages model loading/unloading with clean CUDA memory cycles"""
    _instance = None
    _initialized = False
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(ModelManager, cls).__new__(cls)
        return cls._instance
    
    def __init__(self):
        if self._initialized:
            return
            
        super().__init__()
        logger.info("=== INITIALIZING MODEL MANAGER ===")
        
        self._initialized = True
        self._model_lock = threading.Lock()
        self._current_model = None
        self._cuda_initialized = False
        self._loading = threading.Event()  # Add loading event
        self.state = None
        
        # Initialize model paths
        self.models_dir = Path("models").absolute()
        self.model_files = {
            'LM_SMALL': 'Qwen2.5-Coder-14B-Instruct-Q6_K_L.gguf',
            'LM_LARGE': 'Qwen2.5-Coder-32B-Instruct-Q6_K_L.gguf'
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

    def set_state(self, state: UnifiedState):
        """Set the state object"""
        self.state = state

    def _initialize_cuda(self):
        """Initialize CUDA once"""
        if self._cuda_initialized:
            return
            
        if torch.cuda.is_available():
            try:
                torch.cuda.init()
                torch.cuda.set_device(0)
                device_props = torch.cuda.get_device_properties(0)
                logger.info(f"CUDA Device: {device_props.name}")
                logger.info(f"Total GPU Memory: {device_props.total_memory / 1024**3:.2f} GB")
                self._cuda_initialized = True
                
                # Set environment variables once
                os.environ['CUDA_VISIBLE_DEVICES'] = '0'
                os.environ['GGML_CUDA_NO_PINNED'] = '1'
                os.environ['CUDA_LAUNCH_BLOCKING'] = '1'
            except Exception as e:
                logger.error(f"CUDA initialization error: {e}")
                raise

    def _unload_current_model(self):
        """Fully unload current model and clear CUDA memory"""
        if self._current_model:
            logger.info(f"Unloading model: {self._current_model.model_type}")
            model_ref = weakref.ref(self._current_model)
            del self._current_model
            self._current_model = None
            
            if torch.cuda.is_available():
                try:
                    # Synchronize and clear CUDA memory
                    torch.cuda.synchronize()
                    gc.collect()
                    torch.cuda.empty_cache()
                    torch.cuda.synchronize()
                    
                    # Force Python garbage collection
                    if model_ref() is not None:
                        del model_ref
                        gc.collect()
                    
                    # Log memory status
                    free_memory = torch.cuda.get_device_properties(0).total_memory - torch.cuda.memory_allocated()
                    logger.info(f"Available GPU memory after unload: {free_memory / 1024**3:.2f} GB")
                    
                except Exception as e:
                    logger.error(f"CUDA cleanup error: {e}")
                    raise

    def _load_model(self, model_type: str) -> Optional[Llama]:
        """Load model with proper CUDA initialization and ARM64 compatibility"""
        logger.info(f"\n=== LOADING MODEL [VERBOSE] ===")
        logger.info(f"Requested model type: {model_type}")
        logger.info(f"Model path: {self.models_dir / self.model_files[model_type]}")
        logger.info(f"Current CUDA state: {torch.cuda.is_available()}")
        
        if torch.cuda.is_available():
            try:
                logger.info("Preparing CUDA environment...")
                torch.cuda.synchronize()
                torch.cuda.empty_cache()
                gc.collect()
                
                free_memory = torch.cuda.get_device_properties(0).total_memory - torch.cuda.memory_allocated()
                logger.info(f"Available GPU memory before load: {free_memory / 1024**3:.2f} GB")
                
            except Exception as e:
                logger.error(f"CUDA preparation error: {e}")
                raise

        config = {
            'model_path': str(self.models_dir / self.model_files[model_type]),
            'n_batch': 512,
            'n_threads': os.cpu_count(),
            'n_ctx': 16384,
            'n_gpu_layers': -1,
            'offload_kqv': False,
            'use_mmap': True,
            'use_mlock': False,
            'vocab_only': False,
            'tensor_split': None,
            'rope_scaling': None,
            'embedding_only': False,
            'logits_all': False,
            'use_float32': False
        }
        
        logger.info(f"Model configuration: {config}")
        
        try:
            logger.info("Starting model load with timeout protection...")
            q = queue.Queue()
            
            def load_with_timeout():
                try:
                    logger.info("Initializing model...")
                    model = Llama(**config)
                    model.model_type = model_type
                    logger.info(f"Model initialized with type: {model_type}")
                    return model
                except Exception as e:
                    logger.error(f"Model initialization error: {e}")
                    raise
            
            def wrapper():
                try:
                    model = load_with_timeout()
                    q.put(('success', model))
                except Exception as e:
                    q.put(('error', e))
            
            thread = threading.Thread(target=wrapper)
            thread.daemon = True
            thread.start()
            
            logger.info("Waiting for model load completion...")
            result = q.get(timeout=300)
            
            if result[0] == 'error':
                logger.error(f"Model load failed: {result[1]}")
                raise result[1]
            
            model = result[1]
            logger.info(f"Model {model_type} loaded successfully")
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
        """Switch models with complete memory cleanup"""
        logger.info(f"\n=== ATTEMPTING MODEL SWITCH TO {model_type} ===")
        logger.info(f"[SWITCH] Current model: {self._current_model.model_type if self._current_model else 'None'}")
        logger.info(f"[SWITCH] Lock state: {self._model_lock}")
        
        with self._model_lock:
            try:
                memory_cleared = False
                
                # 1. Clear all state before switching
                if self.state:
                    if self.state.memory:
                        logger.info("[SWITCH] Clearing message memory...")
                        self.state.memory.clear_all()
                        memory_cleared = True
                    
                    if self.state.conversation_manager:
                        logger.info("[SWITCH] Clearing conversation history...")
                        self.state.conversation_manager.clear_all_threads()  # This already saves to file
                        memory_cleared = True
                        
                    # Clear context manager state and caches
                    if hasattr(self.state, 'context_manager') and self.state.context_manager:
                        logger.info("[SWITCH] Clearing context manager state...")
                        self.state.context_manager._contexts.clear()
                        self.state.context_manager._history.clear()
                        self.state.context_manager._cache.cleanup()
                        self.state.context_manager._token_count_cache.cleanup()
                        memory_cleared = True
                    
                    # Removed persistence call since clear_all_threads handles it
                
                # 2. Unload current model and clear CUDA memory
                logger.info("[SWITCH] Unloading current model...")
                if self._current_model:
                    logger.info(f"[SWITCH] Unloading {self._current_model.model_type}")
                    self._unload_current_model()
                
                # 3. Force CUDA memory cleanup
                logger.info("[SWITCH] Clearing CUDA memory...")
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
                    torch.cuda.synchronize()
                    free_memory = torch.cuda.get_device_properties(0).total_memory - torch.cuda.memory_allocated()
                    logger.info(f"[SWITCH] Available GPU memory after cleanup: {free_memory / 1024**3:.2f} GB")
                
                # 4. Load new model
                logger.info(f"[SWITCH] Loading new model {model_type}")
                self._current_model = self._load_model(model_type)
                
                if not self._current_model:
                    raise RuntimeError(f"Failed to load {model_type}")
                
                # 5. Reset model state
                if hasattr(self._current_model, 'reset'):
                    self._current_model.reset()
                
                success_message = ""
                if memory_cleared:
                    success_message = f"Switched to {model_type}. Memory and conversation history cleared."
                else:
                    success_message = f"Switched to {model_type}."
                
                logger.info(f"[SWITCH] Successfully switched to {model_type}")
                return True, success_message
                
            except Exception as e:
                logger.error(f"[SWITCH] Model switch failed: {e}")
                logger.error(f"[SWITCH] Traceback: {traceback.format_exc()}")
                return False, f"Failed to switch model: {str(e)}"

    def determine_model_type(self, message: str, has_code: bool = False) -> Tuple[bool, str]:
        """Determine which model to use based on message"""
        logger.info("\n=== DETERMINE MODEL TYPE ===")
        
        message_lower = message.lower().strip()
        current_type = self._current_model.model_type if self._current_model else None
        
        logger.info(f"Current model: {current_type}")
        logger.info(f"Input message: '{message_lower}'")
        
        # Check for exact model requests
        if message_lower == '@nutonic':  # Only match exact '@nutonic'
            logger.info("Request for Nutonic (LM_LARGE)")
            success = self.switch_model('LM_LARGE')[0]
            return success, "Switching to Nutonic (LM_LARGE)"
        elif message_lower == '@charlotte' or message_lower == '@lotte':  # Match exact '@charlotte' or '@lotte'
            logger.info("Request for Charlotte (LM_SMALL)")
            success = self.switch_model('LM_SMALL')[0]
            return success, "Switching to Charlotte (LM_SMALL)"
        
        # Keep current model for all other cases
        logger.info(f"Keeping current model: {current_type}")
        return True, ""

    def get_current_model(self) -> Optional[Llama]:
        """Get current model without auto-loading"""
        logger.info("\n=== GET_CURRENT_MODEL [EXTREME VERBOSE] ===")
        logger.info(f"[MODEL] Loading state: {self._loading.is_set()}")
        logger.info(f"[MODEL] Lock state: {self._model_lock}")
        logger.info(f"[MODEL] Current model: {self._current_model}")
        
        if self._loading.is_set():
            logger.warning("[MODEL] Model load in progress")
            return None
        
        with self._model_lock:
            if not self._current_model:
                logger.info("[MODEL] No model currently loaded")
                return None
            logger.info(f"[MODEL] Returning model type: {self._current_model.model_type}")
            return self._current_model

    def create_completion(self, *args, **kwargs):
        """Create completion with proper prompt handling"""
        try:
            model = self.get_current_model()
            if model is None:
                raise RuntimeError("No model available")
            
            # Set proper streaming parameters
            if kwargs.get('stream', False):
                kwargs['stream_tokens'] = True  # Stream by tokens instead of chars
            
            # Use standard stop tokens
            if 'stop' not in kwargs:
                kwargs['stop'] = ["<|im_end|>"]
            elif "<|im_end|>" not in kwargs['stop']:
                kwargs['stop'].append("<|im_end|>")
            
            return model.create_completion(*args, **kwargs)
            
        except Exception as e:
            logger.error(f"[COMPLETE] Error: {e}")
            raise

    def create_completion_with_retry(self, *args, **kwargs):
        """Create completion with retries on failure"""
        logger.info("\n=== CREATE COMPLETION WITH RETRY [VERBOSE] ===")
        logger.info(f"Args: {args}")
        logger.info(f"Kwargs: {kwargs}")
        
        max_retries = 3
        retry_delay = 1.0
        is_streaming = kwargs.get('stream', False)
        
        for attempt in range(max_retries):
            try:
                logger.info(f"Attempt {attempt + 1} of {max_retries}")
                
                # Get current model
                model = self.get_current_model()
                if model is None:
                    raise RuntimeError("No model available")
                    
                logger.info(f"Using model type: {model.model_type}")
                
                # Create completion
                response = model.create_completion(*args, **kwargs)
                
                # For streaming responses, return the iterator directly
                if is_streaming:
                    return response
                    
                # For non-streaming, validate the response
                if not response or 'choices' not in response:
                    raise RuntimeError("Invalid response from model")
                    
                logger.info("Completion successful")
                return response
                
            except Exception as e:
                logger.error(f"Attempt {attempt + 1} failed: {e}")
                logger.error(traceback.format_exc())
                
                if attempt < max_retries - 1:
                    logger.info(f"Retrying in {retry_delay} seconds...")
                    time.sleep(retry_delay)
                    retry_delay *= 2  # Exponential backoff
                    
                    # Force cleanup before retry
                    if torch.cuda.is_available():
                        torch.cuda.empty_cache()
                        torch.cuda.synchronize()
                    gc.collect()
                else:
                    logger.error("All retry attempts failed")
                    raise

    def get_current_model_type(self) -> str:
        """Get the type of currently loaded model"""
        logger.info("[MODEL] Getting current model type")
        try:
            with self._model_lock:
                if not self._current_model:
                    logger.info("[MODEL] No model currently loaded")
                    return "none"
                return self._current_model.model_type
        except Exception as e:
            logger.error(f"[MODEL] Error getting model type: {e}")
            return "unknown"

    def set_active_model(self, model_type: str) -> bool:
        """Set the active model type"""
        logger.info(f"[MODEL] Setting active model to: {model_type}")
        try:
            if model_type == "memory":
                return self.switch_model("LM_SMALL")
            elif model_type == "coder":
                return self.switch_model("LM_LARGE")
            else:
                logger.error(f"[MODEL] Invalid model type: {model_type}")
                return False
        except Exception as e:
            logger.error(f"[MODEL] Error setting active model: {e}")
            return False

class MessageQueue:
    """Thread-safe message queue with validation"""
    def __init__(self, max_size: int = 1000):
        self._queue = queue.Queue(maxsize=max_size)
        self._dead_letter = queue.Queue()
        self._processing = set()
        self._lock = threading.Lock()
        self._shutdown = threading.Event()
        self._stats = ThreadStats()
        self.MAX_RETRIES = 3
        self.RETRY_DELAY = 1.0
        self._message_counter = 0

    def add(self, message: dict) -> bool:
        if not self._validate_message(message):
            logger.error("Invalid message format")
            return False

        with self._lock:
            try:
                self._message_counter += 1
                message['id'] = self._message_counter
                message['timestamp'] = time.time()
                message['retries'] = 0
                self._queue.put((message.get('thread_id', 'default'), message))
                self._stats.active += 1
                self._stats.last_activity = time.time()
                return True
            except queue.Full:
                logger.error("Message queue full")
                return False

    def get(self, timeout: float = 1.0) -> Optional[Tuple[str, dict]]:
        try:
            thread_id, message = self._queue.get(timeout=timeout)
            with self._lock:
                self._processing.add(message['id'])
            return thread_id, message
        except queue.Empty:
            return None

    def complete(self, message_id: int):
        with self._lock:
            self._processing.discard(message_id)
            self._stats.active -= 1
            self._queue.task_done()

    def fail(self, message: dict):
        with self._lock:
            self._processing.discard(message['id'])
            self._stats.active -= 1
            if message.get('retries', 0) < self.MAX_RETRIES:
                message['retries'] = message.get('retries', 0) + 1
                self._queue.put((message.get('thread_id', 'default'), message))
            else:
                self._dead_letter.put(message)

    def _validate_message(self, message: dict) -> bool:
        required = {'thread_id', 'content', 'role'}
        return all(k in message for k in required)

    def stop(self):
        """Stop queue processing"""
        self._shutdown.set()
        with self._lock:
            while not self._queue.empty():
                try:
                    self._queue.get_nowait()
                    self._queue.task_done()
                except queue.Empty:
                    break

    def clear(self):
        """Clear all queues immediately"""
        with self._lock:
            while not self._queue.empty():
                try:
                    self._queue.get_nowait()
                    self._queue.task_done()
                except queue.Empty:
                    break
            while not self._dead_letter.empty():
                try:
                    self._dead_letter.get_nowait()
                except queue.Empty:
                    break
            self._processing.clear()

class DuplicateDetector:
    """Detects duplicate or near-duplicate messages using content hashing and semantic similarity"""
    def __init__(self, ttl: int = 3600):
        self._hash_cache: Dict[str, float] = {}  # hash -> timestamp
        self._ttl = ttl
        self._lock = threading.Lock()

    def _clean_content(self, content: str) -> str:
        """Normalize content for comparison"""
        # Convert to lowercase and normalize whitespace
        content = re.sub(r'\s+', ' ', content.lower().strip())
        # Remove common punctuation variations
        content = re.sub(r'[,.!?;:"\']', '', content)
        # Remove timestamps and dates
        content = re.sub(r'\d{1,2}:\d{2}(:\d{2})?', '', content)
        content = re.sub(r'\d{4}-\d{2}-\d{2}', '', content)
        return content

    def _compute_hash(self, content: str) -> str:
        """Compute stable hash of normalized content"""
        cleaned = self._clean_content(content)
        return hashlib.blake2b(cleaned.encode(), digest_size=16).hexdigest()

    def _clean_expired(self) -> None:
        """Remove expired hashes"""
        now = time.time()
        with self._lock:
            self._hash_cache = {
                h: ts for h, ts in self._hash_cache.items()
                if now - ts < self._ttl
            }

    def is_duplicate(self, content: str, thread_id: str) -> bool:
        """Check if content is a duplicate"""
        if not content:
            return False

        self._clean_expired()
        
        # Compute content hash
        content_hash = self._compute_hash(content)
        
        with self._lock:
            # Check for exact match
            if content_hash in self._hash_cache:
                return True
                
            # Store new hash
            self._hash_cache[content_hash] = time.time()
            return False

class MessageManager(BaseManager):
    """Manages conversation messages and threads"""
    def __init__(self):
        super().__init__()
        self._messages = defaultdict(list)  # thread_id -> list of messages
        self._lock = threading.Lock()
        
    def add_message(self, message: dict) -> bool:
        """Add a message to a thread"""
        try:
            thread_id = message.get('thread_id', 'default')
            with self._lock:
                self._messages[thread_id].append(message)
            return True
        except Exception as e:
            logger.error(f"Error adding message: {e}")
            return False
            
    def get_thread_messages(self, thread_id: str) -> List[dict]:
        """Get all messages for a thread"""
        with self._lock:
            return self._messages.get(thread_id, []).copy()
            
    def clear_thread(self, thread_id: str) -> bool:
        """Clear messages for a specific thread"""
        try:
            with self._lock:
                if thread_id in self._messages:
                    del self._messages[thread_id]
            return True
        except Exception as e:
            logger.error(f"Error clearing thread {thread_id}: {e}")
            return False
            
    def clear_all_threads(self) -> bool:
        """Clear all conversation threads"""
        try:
            with self._lock:
                self._messages.clear()
            logger.info("All conversation threads cleared")
            return True
        except Exception as e:
            logger.error(f"Error clearing all threads: {e}")
            return False
            
    def _cleanup_impl(self):
        """Cleanup implementation"""
        with self._lock:
            self._messages.clear()

class ContextManager(BaseManager):
    """Enhanced context management with smart selection and compression"""
    def __init__(self, state: UnifiedState):
        super().__init__()
        self._cache = ExpiringCache(max_size=1000, ttl=300)
        self.state = state
        self._token_tracker = TokenTracker(safety_margin=50)  # Changed from 200 to 50
        self._importance_weights = {
            'user_mention': 2.0,
            'question': 1.5,
            'recent': 1.3,
            'code': 1.2,
            'base': 1.0,
            'error': 1.8,  # Higher weight for error messages
            'continuation': 1.4  # For conversation flow
        }
        self._max_context_lengths = {
            'LM_SMALL': MAX_CONTEXT_TOKENS_SMALL,
            'LM_LARGE': MAX_CONTEXT_TOKENS_LARGE
        }
        self._token_count_cache = ExpiringCache(max_size=10000, ttl=3600)
        self._contexts = {}
        self._history = {}
        logger.info("[CONTEXT] ContextManager initialized")

    def _count_tokens_accurately(self, text: str) -> int:
        """More accurate token counting using model's tokenizer"""
        cache_key = hashlib.md5(text.encode()).hexdigest()
        
        if cached := self._token_count_cache.get(cache_key):
            return cached
        
        try:
            # Get the current model through the model manager
            model_manager = self.state.model_manager
            if not model_manager:
                # Fallback to simple estimation if no model manager
                count = len(re.findall(r'\w+|[^\w\s]', text))
                self._token_count_cache.set(cache_key, count)
                return count
                
            model = model_manager.get_current_model()
            if not model:
                # Fallback to simple estimation if no model
                count = len(re.findall(r'\w+|[^\w\s]', text))
                self._token_count_cache.set(cache_key, count)
                return count
            
            # Use actual model tokenizer
            token_count = len(model.tokenize(text.encode()))
            self._token_count_cache.set(cache_key, token_count)
            return token_count
            
        except Exception as e:
            logger.error(f"Token counting error: {e}")
            # Fallback to simple estimation
            count = len(re.findall(r'\w+|[^\w\s]', text))
            self._token_count_cache.set(cache_key, count)
            return count

    def _score_message(self, message: Dict, current_time: float) -> float:
        """Enhanced message scoring with more factors"""
        score = self._importance_weights['base']
        content = message.get('content', '').lower()
        
        # Time decay factor (exponential decay over 1 hour)
        time_diff = current_time - message.get('timestamp', current_time)
        time_factor = math.exp(-time_diff / 3600)
        
        # Enhanced importance factors
        if '@' in content or 'you' in content.split():
            score *= self._importance_weights['user_mention']
        if '?' in content:
            score *= self._importance_weights['question']
        if any(indicator in content for indicator in ['code', 'function', 'error', 'bug']):
            score *= self._importance_weights['code']
        if any(error_term in content for error_term in ['error', 'exception', 'failed', 'crash']):
            score *= self._importance_weights['error']
        
        # Conversation flow scoring
        if message.get('in_response_to') or message.get('addressing'):
            score *= self._importance_weights['continuation']
        
        # Recent message bonus
        if time_diff < 300:  # Last 5 minutes
            score *= 1.5
        
        score *= time_factor
        return score

    def _select_context_messages(self, messages: List[Dict], limit: int) -> List[Dict]:
        """Select most relevant messages for context"""
        logger.info("\n=== SELECT_CONTEXT_MESSAGES: ENTRY POINT ===")
        logger.info(f"[SELECT] Total messages: {len(messages)}")
        logger.info(f"[SELECT] Requested limit: {limit}")
        
        current_time = time.time()
        logger.info(f"[SELECT] Current time: {current_time}")
        
        # Score and log each message
        scored_messages = []
        for idx, msg in enumerate(messages):
            score = self._score_message(msg, current_time)
            scored_messages.append((score, msg))
            
            logger.info(f"[SELECT] Message {idx + 1}:")
            logger.info(f"[SELECT] - Role: {msg.get('role', 'unknown')}")
            logger.info(f"[SELECT] - Time diff: {current_time - msg.get('timestamp', current_time):.2f}s")
            logger.info(f"[SELECT] - Score: {score:.4f}")
            logger.info(f"[SELECT] - Content preview: {msg.get('content', '')[:100]}...")
        
        # Sort and select top messages
        scored_messages.sort(reverse=True, key=lambda x: x[0])
        selected = [msg for _, msg in scored_messages[:limit]]
        
        logger.info(f"[SELECT] Selected {len(selected)} messages")
        logger.info("[SELECT] Selected messages preview:")
        for idx, msg in enumerate(selected):
            logger.info(f"[SELECT] {idx + 1}. {msg.get('role', 'unknown')}: {msg.get('content', '')[:100]}...")
        
        return selected

    def _compress_context(self, context: str, model_type: str) -> str:
        """Improved context compression with token awareness"""
        max_tokens = self._max_context_lengths.get(model_type, MAX_CONTEXT_TOKENS_SMALL)
        current_tokens = self._count_tokens_accurately(context)
        
        if current_tokens <= max_tokens:
            return context

        sections = re.split(r'(<rewritten_message><rewritten_role>.*?</rewritten_message>)', context, flags=re.DOTALL)
        sections = [s for s in sections if s.strip()]
        
        # Always keep system prompt and last message
        system_prompt = next((s for s in sections if '<rewritten_message><rewritten_role>system' in s), sections[0])
        last_message = sections[-1]
        
        # Calculate available tokens more accurately
        used_tokens = (
            self._count_tokens_accurately(system_prompt) +
            self._count_tokens_accurately(last_message)
        )
        available_tokens = max_tokens - used_tokens
        
        middle_sections = [s for s in sections[1:-1] if s not in (system_prompt, last_message)]
        if not middle_sections:
            return system_prompt + last_message
            
        tokens_per_section = available_tokens // len(middle_sections)
        
        compressed_sections = []
        for section in middle_sections:
            section_tokens = self._count_tokens_accurately(section)
            if section_tokens > tokens_per_section:
                words = re.findall(r'\w+|[^\w\s]', section)
                keep_count = tokens_per_section // 2
                compressed = ' '.join(words[:keep_count] + ['...'] + words[-keep_count:])
                # Verify compressed section token count
                while self._count_tokens_accurately(compressed) > tokens_per_section:
                    keep_count = int(keep_count * 0.9)  # Reduce by 10%
                    compressed = ' '.join(words[:keep_count] + ['...'] + words[-keep_count:])
                compressed_sections.append(compressed)
            else:
                compressed_sections.append(section)
                
        return system_prompt + ''.join(compressed_sections) + last_message

    def build_context(self, thread_id: str, message: str) -> str:
        """Build context with token tracking"""
        logger.info("\n=== BUILD_CONTEXT WITH TOKEN TRACKING ===")
        try:
            # 1. Get model type and initialize
            model = self.state.model_manager.get_current_model()
            if not model:
                raise RuntimeError("No model available")
            model_type = model.model_type
            
            # 2. Reset token counters at start
            self._token_tracker.reset_counts()
            logger.info("[CTX] Token counters reset")
            
            # 3. Process system prompt
            system_prompt = self._get_system_prompt()
            prompt_tokens = self._count_tokens_accurately(system_prompt)
            
            # 4. Check system prompt against limit
            if self._token_tracker.would_exceed_limit(model_type, prompt_tokens):
                logger.warning(f"[CTX] System prompt ({prompt_tokens} tokens) would exceed limit")
                return self._build_minimal_context(message)
            
            # 5. Start building context
            context = f"<|im_start|>system\n{system_prompt}<|im_end|>\n"
            self._token_tracker.add_tokens(prompt_tokens)
            logger.info(f"[CTX] System prompt added: {prompt_tokens} tokens")
            
            # 6. Process history with token awareness
            history = self._get_thread_history(thread_id)
            if history:
                history_tokens = self._count_tokens_accurately(history)
                remaining_tokens = self._token_tracker.get_remaining_tokens(model_type)
                
                if history_tokens > remaining_tokens:
                    logger.warning(f"[CTX] History ({history_tokens} tokens) exceeds remaining space ({remaining_tokens} tokens)")
                    history = self._truncate_history(history, remaining_tokens)
                    history_tokens = self._count_tokens_accurately(history)
                
                context += f"{history}\n"
                self._token_tracker.add_tokens(history_tokens)
                logger.info(f"[CTX] History added: {history_tokens} tokens")
            
            # 7. Process current message
            message_tokens = self._count_tokens_accurately(message)
            remaining_tokens = self._token_tracker.get_remaining_tokens(model_type)
            
            if message_tokens > remaining_tokens:
                logger.warning(f"[CTX] Message ({message_tokens} tokens) exceeds remaining space ({remaining_tokens} tokens)")
                message = self._truncate_message(message, remaining_tokens)
                message_tokens = self._count_tokens_accurately(message)
            
            # 8. Add message and assistant tag
            context += f"<|im_start|>user\n{message}<|im_end|>\n<|im_start|>assistant\n"
            self._token_tracker.add_tokens(message_tokens)
            
            # 9. Log final token counts
            total_tokens = self._token_tracker.current_tokens
            remaining = self._token_tracker.get_remaining_tokens(model_type)
            generation_remaining = MAX_GENERATION_TOKENS
            
            logger.info(f"[CTX] === Token Usage Summary ===")
            logger.info(f"[CTX] Total context tokens: {total_tokens}")
            logger.info(f"[CTX] Remaining context space: {remaining}")
            logger.info(f"[CTX] Available for generation: {generation_remaining}")
            logger.info(f"[CTX] Safety margin: {self._token_tracker.safety_margin}")
            
            return context
            
        except Exception as e:
            logger.error(f"[CTX_BUILD] Error: {e}")
            logger.error(traceback.format_exc())
            return self._build_minimal_context(message)

    def _build_minimal_context(self, message: str) -> str:
        """Build minimal context when token limits are exceeded"""
        return f"<|im_start|>system\n{self._get_system_prompt()}<|im_end|>\n<|im_start|>user\n{message}<|im_end|>\n<|im_start|>assistant\n"

    def _truncate_history(self, history: str, max_tokens: int) -> str:
        """Truncate history to fit within token limit"""
        if self._count_tokens_accurately(history) <= max_tokens:
            return history
            
        messages = history.split("<|im_end|>")
        truncated = []
        current_tokens = 0
        
        for msg in reversed(messages):  # Start from most recent
            msg_tokens = self._count_tokens_accurately(msg)
            if current_tokens + msg_tokens <= max_tokens:
                truncated.insert(0, msg)
                current_tokens += msg_tokens
            else:
                break
                
        return "<|im_end|>".join(truncated)

    def _truncate_message(self, message: str, max_tokens: int) -> str:
        """Truncate message to fit within token limit"""
        if self._count_tokens_accurately(message) <= max_tokens:
            return message
            
        words = message.split()
        truncated = []
        current_tokens = 0
        
        for word in words:
            word_tokens = self._count_tokens_accurately(word + ' ')
            if current_tokens + word_tokens <= max_tokens:
                truncated.append(word)
                current_tokens += word_tokens
            else:
                break
                
        return ' '.join(truncated) + '...'

    def _get_system_prompt(self) -> str:
        """Get appropriate system prompt based on active model"""
        logger.info("\n=== GETTING SYSTEM PROMPT [VERBOSE] ===")
        try:
            # Access model_manager directly as an attribute
            model_manager = self.state.model_manager
            logger.info(f"Retrieved model_manager: {model_manager}")
            
            if not model_manager:
                logger.info("No model manager found, defaulting to LM_SMALL")
                return LM_SMALL_SYSTEM_PROMPT
            
            current_model = model_manager.get_current_model()
            logger.info(f"Retrieved current_model: {current_model}")
            
            if not current_model:
                logger.info("No current model, defaulting to LM_SMALL")
                return LM_SMALL_SYSTEM_PROMPT
            
            model_type = current_model.model_type
            logger.info(f"Current model type: {model_type}")
            
            prompt = LM_LARGE_SYSTEM_PROMPT if model_type == 'LM_LARGE' else LM_SMALL_SYSTEM_PROMPT
            logger.info(f"Selected prompt for {model_type}: {prompt[:100]}...")
            return prompt
            
        except Exception as e:
            logger.error(f"Error getting system prompt: {e}")
            logger.error(traceback.format_exc())
            logger.info("Falling back to LM_SMALL prompt")
            return LM_SMALL_SYSTEM_PROMPT

    def _cleanup_impl(self):
        """Cleanup implementation"""
        logger.info("Cleaning up context manager...")
        try:
            self._cache.cleanup()
            self._token_count_cache.cleanup()
            self._contexts.clear()
            self._history.clear()
            
            # Force cache cleanup
            gc.collect()
        except Exception as e:
            logger.error(f"Context cleanup error: {e}")
        finally:
            logger.info("Context cleanup complete")

    def _get_thread_history(self, thread_id: str) -> str:
        """Get conversation history with proper token formatting"""
        logger.info("\n=== GET_THREAD_HISTORY: EXTREME VERBOSE ===")
        logger.info(f"[HIST] Thread ID: {thread_id}")
        
        try:
            # Get history from conversation manager
            history = self.state.conversation_manager.get_thread_history(thread_id)
            
            # The history should already be properly formatted from ConversationManager
            # Just log and return it
            logger.info(f"[HIST] Retrieved history: {history}")
            return history
                
        except Exception as e:
            logger.error(f"[HIST] Error getting history: {e}")
            logger.error(f"[HIST] Error type: {type(e)}")
            logger.error(f"[HIST] Error args: {e.args}")
            logger.error(f"[HIST] Traceback: {traceback.format_exc()}")
            return ""

    def clear_caches(self):
        """Explicitly clear all caches"""
        with self._lock:
            self._cache.cleanup()
            self._token_count_cache.cleanup()
            self._contexts.clear()
            self._history.clear()
            gc.collect()

class ExpiringCache:
    """Thread-safe cache with TTL and size limits"""
    def __init__(self, max_size: int, ttl: int):
        self._cache = {}
        self._max_size = max_size
        self._ttl = ttl
        self._lock = threading.Lock()
        self._shutdown = threading.Event()
        self._start_cleanup()

    def _start_cleanup(self):
        """Start background cleanup thread"""
        def cleanup_loop():
            while not self._shutdown.is_set():
                try:
                    with self._lock:
                        current_time = time.time()
                        expired = [
                            key for key, item in self._cache.items()
                            if current_time - item['timestamp'] > self._ttl
                        ]
                        for key in expired:
                            del self._cache[key]
                except Exception as e:
                    logger.error(f"Cache cleanup error: {e}")
                finally:
                    time.sleep(60)  # Run cleanup every minute

        threading.Thread(target=cleanup_loop, daemon=True).start()

    def cleanup(self):
        """Stop cleanup thread and clear cache"""
        self._shutdown.set()
        with self._lock:
            self._cache.clear()

    def get(self, key: str) -> Optional[Any]:
        with self._lock:
            if key not in self._cache:
                return None
            item = self._cache[key]
            if time.time() - item['timestamp'] > self._ttl:
                del self._cache[key]
                return None
            return item['value']

    def set(self, key: str, value: Any):
        with self._lock:
            self._cache[key] = {
                'value': value,
                'timestamp': time.time()
            }
            if len(self._cache) > self._max_size:
                self._evict_oldest()

    def _evict_oldest(self):
        if not self._cache:
            return
        oldest = min(self._cache.items(), key=lambda x: x[1]['timestamp'])[0]
        del self._cache[oldest]

class Application:
    """Main application class"""
    _instance = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(Application, cls).__new__(cls)
        return cls._instance
    
    def __init__(self):
        if hasattr(self, '_initialized'):
            return
            
        logger.info("\n=== INITIALIZING APPLICATION ===")
        
        try:
            # Initialize storage path
            self.storage_dir = Path("conversation_history").absolute()
            self.storage_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"Initializing storage at: {self.storage_dir}")
            
            # Initialize state
            state_file = self.storage_dir / 'unified_state.json'
            self.state = UnifiedState(state_file)
            
            # Initialize components in correct order
            self.memory = MessageMemory()
            self.state.set_memory(self.memory)
            
            self.model_manager = ModelManager()
            self.state.set_model_manager(self.model_manager)
            self.model_manager.set_state(self.state)
            
            # Pass storage_dir instead of state to ConversationManager
            self.conversation_manager = ConversationManager(self.storage_dir)
            self.state.set_conversation_manager(self.conversation_manager)
            
            self.message_manager = MessageManager()
            self.context_manager = ContextManager(self.state)
            
            # Verify initialization
            self.state.verify_initialization()
            
            self._initialized = True
            logger.info("Application initialized successfully")
            
        except Exception as e:
            logger.error(f"Application initialization failed: {e}")
            logger.error(traceback.format_exc())
            raise RuntimeError(f"Failed to initialize application: {e}")

    def process_message(self, message: str, thread_id: str = 'default') -> str:
        """Process incoming message and return response"""
        logger.info("\n=== PROCESS_MESSAGE: EXTREME VERBOSE ===")
        logger.info(f"[PROCESS] Input message: '{message}'")
        logger.info(f"[PROCESS] Thread ID: {thread_id}")
        logger.info(f"[PROCESS] Current state: {vars(self)}")
        
        try:
            # Initialize thread if needed
            logger.info("[PROCESS] Checking thread initialization...")
            if thread_id not in self.conversation_manager._conversations:
                logger.info("[PROCESS] Creating new conversation thread")
                self.conversation_manager.create_thread(thread_id)
            
            logger.info("[PROCESS] Thread state after initialization:")
            logger.info(f"[PROCESS] - Conversations: {self.conversation_manager._conversations}")
            logger.info(f"[PROCESS] - History: {self.conversation_manager._history}")
            
            # Build context
            logger.info("[PROCESS] Building context...")
            context = self.context_manager.build_context(thread_id, message)
            logger.info(f"[PROCESS] Context built, length: {len(context)}")
            logger.info(f"[PROCESS] Context preview: {context[:500]}")
            
            # Get model and generate response
            logger.info("[PROCESS] Getting model for response...")
            model = self.model_manager.get_current_model()
            if not model:
                logger.error("[PROCESS] No model available!")
                raise RuntimeError("No model available")
            
            logger.info(f"[PROCESS] Generating response with {model.model_type}")
            response = model.create_completion(
                context,
                max_tokens=1024,
                stop=["<|im_end|>"],
                echo=False
            )
            
            # Get the response text
            response_text = response['choices'][0]['text']
            logger.info("[PROCESS] Response generated successfully")
            
            # Store assistant response in history
            logger.info("[PROCESS] Storing assistant response in history")
            assistant_message = {
                'role': 'assistant',
                'content': response_text,
                'timestamp': time.time(),
                'thread_id': thread_id,
                'model_type': model.model_type
            }
            success = self.conversation_manager.add_message(thread_id, assistant_message)
            logger.info(f"[PROCESS] Assistant message added: {success}")
            
            # Verify history was updated
            history = self.conversation_manager.get_thread_history(thread_id)
            logger.info(f"[PROCESS] Final history size: {len(history)} messages")
            logger.info("[PROCESS] Current conversation history:")
            for idx, msg in enumerate(history):
                logger.info(f"[PROCESS] Message {idx + 1}:")
                logger.info(f"[PROCESS] - Role: {msg.get('role')}")
                logger.info(f"[PROCESS] - Content: {msg.get('content')[:100]}...")
            
            # Force state persistence
            self.conversation_manager._persist_state()
            logger.info("[PROCESS] Conversation state persisted")
            
            return response_text
            
        except Exception as e:
            logger.error(f"[PROCESS] CRITICAL ERROR: {e}")
            logger.error(f"[PROCESS] Error type: {type(e)}")
            logger.error(f"[PROCESS] Error args: {e.args}")
            logger.error(f"[PROCESS] Traceback: {traceback.format_exc()}")
            logger.error(f"[PROCESS] State dump: {vars(self)}")
            return "I apologize, but I encountered an error processing your message."

    def cleanup(self):
        """Simple cleanup logging"""
        logger.info("Application cleanup complete")

    def signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        logger.info(f"\n=== RECEIVED SIGNAL {signum} ===")
        sys.exit(0)

@dataclass
class MessageValidationResult:
    """Result of message validation"""
    is_valid: bool
    errors: List[str]
    warnings: List[str]

class MessageValidator:
    """Validates message structure and content"""
    def __init__(self):
        self.required_fields = {'content', 'role', 'thread_id'}
        self.valid_roles = {'user', 'assistant', 'system'}
        self.max_content_length = MAX_CONTEXT_TOKENS_LARGE  # Largest possible context
        
    def validate(self, message: Dict) -> MessageValidationResult:
        errors = []
        warnings = []
        
        # Check required fields
        missing_fields = self.required_fields - set(message.keys())
        if missing_fields:
            errors.append(f"Missing required fields: {missing_fields}")
            
        # Validate role
        role = message.get('role')
        if role and role not in self.valid_roles:
            errors.append(f"Invalid role: {role}")
            
        # Validate content
        content = message.get('content', '')
        if not content:
            errors.append("Empty content")
        elif len(content) > self.max_content_length:
            errors.append(f"Content exceeds max length of {self.max_content_length}")
            
        # Check thread_id format
        thread_id = message.get('thread_id', '')
        if not thread_id or not isinstance(thread_id, str):
            errors.append("Invalid thread_id")
            
        # Additional validations
        if 'timestamp' not in message:
            warnings.append("Missing timestamp")
        if role == 'assistant' and 'model_type' not in message:
            warnings.append("Assistant message missing model_type")
            
        return MessageValidationResult(
            is_valid=len(errors) == 0,
            errors=errors,
            warnings=warnings
        )

@contextmanager
def state_transaction(state: UnifiedState):
    """Provides transaction-like behavior for state updates"""
    snapshot = deepcopy(state._state)
    try:
        yield
    except Exception as e:
        logger.error(f"Transaction failed: {e}")
        state._state = snapshot
        raise
    finally:
        if state._state != snapshot:
            logger.info("State changed, triggering save")
            state.update('last_save', time.time())

def _check_technical_content(self, content: str) -> bool:
    """Check if content contains complex technical discussions"""
    technical_indicators = [
        r'\b(?:theorem|proof|equation|algorithm|implementation|architecture)\b',
        r'[∀∃∈∉∋∌∩∪⊂⊃⊆⊇≈≠≡≢]',
        r'\b(?:physics|chemistry|engineering|computer science)\b',
        r'(?:class|function|method|interface)\s+\w+\s*[({]'
    ]
    
    return any(re.search(pattern, content, re.IGNORECASE) for pattern in technical_indicators)

def check_gpu_memory():
    """Check current GPU memory usage"""
    if torch.cuda.is_available():
        for i in range(torch.cuda.device_count()):
            total = torch.cuda.get_device_properties(i).total_memory / 1024**3
            used = torch.cuda.memory_allocated(i) / 1024**3
            cached = torch.cuda.memory_reserved(i) / 1024**3
            logger.info(f"GPU {i}: Total {total:.2f}GB, Used {used:.2f}GB, Cached {cached:.2f}GB")

class ConversationManager:
    def __init__(self, storage_path: Path):
        self.storage_path = storage_path
        self.storage_path.mkdir(parents=True, exist_ok=True)
        self.conversations_file = self.storage_path / "conversations.json"
        self.conversations = self._load_conversations()
        self._lock = threading.Lock()
        self.max_history = 5  # Keep last 5 messages
        self.max_duplicates = 2  # Allow up to 2 duplicates

    def _load_conversations(self) -> dict:
        """Load conversations from JSON file"""
        if self.conversations_file.exists():
            try:
                with open(self.conversations_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"Error loading conversations: {e}")
                return {}
        return {}

    def _save_conversations(self):
        """Save conversations to JSON file"""
        try:
            with open(self.conversations_file, 'w') as f:
                json.dump(self.conversations, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving conversations: {e}")

    def add_message(self, thread_id: str, message: dict):
        """Add a message to conversation history with deduplication"""
        with self._lock:
            if thread_id not in self.conversations:
                self.conversations[thread_id] = []
            
            # Check for empty content
            content = message.get('content', '').strip()
            if not content:
                return
            
            # Get existing messages for this thread
            thread_messages = self.conversations[thread_id]
            
            # Count recent duplicates (only check last 5 messages)
            recent_duplicates = sum(
                1 for msg in thread_messages[-5:]
                if msg.get('role') == message.get('role') and 
                msg.get('content', '').strip() == content
            )
            
            # Skip if too many duplicates
            if recent_duplicates >= self.max_duplicates:
                logger.info(f"[CONV] Too many duplicates of message: {content}")
                return
            
            # Add message and trim history
            self.conversations[thread_id].append(message)
            self.conversations[thread_id] = self.conversations[thread_id][-self.max_history:]
            self._save_conversations()

    def get_thread_history(self, thread_id: str) -> str:
        """Get conversation history for prompt context"""
        messages = self.conversations.get(thread_id, [])
        if not messages:
            return ""
        
        # Format messages with proper tags
        formatted = []
        for msg in messages:
            role = msg.get('role', 'user')
            content = msg.get('content', '').strip()
            if content:  # Only include non-empty messages
                formatted.append(f"<|im_start|>{role}\n{content}<|im_end|>")
        
        # Join with single newlines
        return "\n".join(formatted)

    def save_response(self, response_buffer: List[str], thread_id: str, model_type: str = None):
        """Save assistant response"""
        try:
            # Combine response buffer into single text
            response_text = ''.join(response_buffer).strip()
            if not response_text:
                return
            
            # Create message object
            message = {
                'role': 'assistant',
                'content': response_text,
                'timestamp': time.time(),
                'thread_id': thread_id,
                'model_type': model_type or 'unknown'
            }
            
            # Add message using standard add_message method
            self.add_message(thread_id, message)
            
        except Exception as e:
            logger.error(f"Error saving response: {e}")
            logger.error(traceback.format_exc())

    def clear_all(self):
        """Clear all conversations"""
        self.conversations.clear()
        self._save_conversations()

    # Add clear_all_threads method
    def clear_all_threads(self) -> bool:
        """Clear all conversation threads"""
        try:
            with self._lock:
                self.conversations.clear()
                self._save_conversations()
            logger.info("All conversation threads cleared")
            return True
        except Exception as e:
            logger.error(f"Error clearing all threads: {e}")
            return False

# Initialize memory saver
memory = MemorySaver()

# Add after the imports
class TokenTracker:
    """Tracks token usage and ensures we stay within limits"""
    def __init__(self, safety_margin: int = 50):  # Changed from 200 to 50
        self._lock = threading.Lock()
        self.safety_margin = safety_margin
        self.reset_counts()

    def reset_counts(self):
        """Reset token counters"""
        with self._lock:
            self.current_tokens = 0
            self.max_seen = 0
            self.generation_tokens = 0  # Add tracking for generation tokens

    def add_tokens(self, count: int, is_generation: bool = False) -> bool:
        """Add tokens and check if we're approaching limits"""
        with self._lock:
            if is_generation:
                self.generation_tokens += count
                return self.generation_tokens <= MAX_GENERATION_TOKENS
            else:
                self.current_tokens += count
                self.max_seen = max(self.max_seen, self.current_tokens)
                return self.current_tokens

    def would_exceed_limit(self, model_type: str, additional_tokens: int, is_generation: bool = False) -> bool:
        """Check if adding tokens would exceed limit"""
        if is_generation:
            return (self.generation_tokens + additional_tokens) > MAX_GENERATION_TOKENS
            
        max_tokens = MAX_CONTEXT_TOKENS_LARGE if model_type == 'LM_LARGE' else MAX_CONTEXT_TOKENS_SMALL
        safe_limit = max_tokens - self.safety_margin
        return (self.current_tokens + additional_tokens) > safe_limit

    def get_remaining_tokens(self, model_type: str, for_generation: bool = False) -> int:
        """Get remaining available tokens"""
        if for_generation:
            return MAX_GENERATION_TOKENS - self.generation_tokens
            
        max_tokens = MAX_CONTEXT_TOKENS_LARGE if model_type == 'LM_LARGE' else MAX_CONTEXT_TOKENS_SMALL
        return max_tokens - self.safety_margin - self.current_tokens
