import json
import os
import threading
import tiktoken
import torch
from datetime import datetime
from llama_cpp import Llama
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Iterator
import re
import traceback
import time

# Configuration settings
CODER_GPU_LAYERS = 55       # Reduced from 45 to save VRAM
FAST_GPU_LAYERS = 37        # Reduced from 32 to save VRAM

# Memory settings
MAX_MEMORIES = 50           # Max messages to keep per thread
MAX_CONTEXT_TOKENS = 32768  # Model's context window
MAX_ANALYSIS_TOKENS = 1000
MIN_ANALYSIS_TOKENS = 100
ANALYSIS_TRUNCATE_PERCENT = 0.1  # 10%
FALLBACK_CHAR_LIMIT = 1000

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
        """Initialize model manager"""
        self._current_model = None
        self._model_type = None
        self._lock = threading.Lock()
        
        # Calculate GPU memory and layers
        if torch.cuda.is_available():
            self.gpu_memory = torch.cuda.get_device_properties(0).total_memory / (1024**3)
            print(f"Total GPU memory: {self.gpu_memory:.2f}GB")
            
            available_memory = (self.gpu_memory - 2) * 0.9
            self.coder_gpu_layers = min(CODER_GPU_LAYERS, int(available_memory / 0.35))
            self.fast_gpu_layers = min(FAST_GPU_LAYERS, int(available_memory / 0.2))
            
            print(f"Adjusted GPU layers - Coder: {self.coder_gpu_layers}, Fast: {self.fast_gpu_layers}")
        else:
            self.coder_gpu_layers = 0
            self.fast_gpu_layers = 0
        
        self._setup_model_paths()
        # Don't load model here - let it be loaded on first request

    def _setup_model_paths(self):
        """Setup and validate model paths"""
        Path("./models").mkdir(exist_ok=True)
        self.coder_model_path = str(Path("./models/Qwen2.5-Coder-32B-Instruct-Q5_K_L.gguf").absolute())
        self.fast_model_path = str(Path("./models/Replete-LLM-V2.5-Qwen-14b-Q5_K_S.gguf").absolute())
        
        if not Path(self.coder_model_path).exists():
            raise FileNotFoundError(f"Coder model not found: {self.coder_model_path}")
        if not Path(self.fast_model_path).exists():
            raise FileNotFoundError(f"Fast model not found: {self.fast_model_path}")

    def _unload_current_model(self):
        """Single source of truth for model cleanup"""
        try:
            if self._current_model:
                print(f"Unloading {self._model_type} model...")
                del self._current_model
                self._current_model = None
                self._model_type = None
                
                if torch.cuda.is_available():
                    torch.cuda.synchronize()
                    torch.cuda.empty_cache()
                    import gc
                    gc.collect()
                    torch.cuda.synchronize()
                    
                    allocated = torch.cuda.memory_allocated()/1024**3
                    reserved = torch.cuda.memory_reserved()/1024**3
                    print(f"CUDA memory after cleanup: {allocated:.2f}GB allocated, {reserved:.2f}GB reserved")
                
                time.sleep(2)
        except Exception as e:
            print(f"Error during model unload: {e}")
            if self._current_model:
                del self._current_model
                self._current_model = None
                self._model_type = None
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
                    torch.cuda.synchronize()

    def get_coder_model(self) -> Llama:
        """Get the coder model, ensuring proper cleanup of memory model"""
        with self._lock:
            try:
                if self._model_type == "Main":
                    return self._current_model
                
                print("Switching to coder model...")
                print(f"Initial CUDA memory: {torch.cuda.memory_allocated()/1024**3:.2f}GB")
                
                # Unload current model and clean memory
                self._unload_current_model()
                
                # Load coder model with adjusted layers
                print(f"Loading coder model with {self.coder_gpu_layers} GPU layers")
                self._current_model = Llama(
                    model_path=self.coder_model_path,
                    n_ctx=MAX_CONTEXT_TOKENS,
                    n_threads=os.cpu_count(),
                    n_gpu_layers=self.coder_gpu_layers,
                    main_gpu=0,
                    use_mmap=True,
                    use_mlock=False,
                    vocab_only=False,
                    attention_type=2,  # Enable Flash Attention 2
                    dtype='bfloat16'  # Required for Flash Attention 2
                )
                self._model_type = "Main"
                print(f"Final CUDA memory: {torch.cuda.memory_allocated()/1024**3:.2f}GB")
                return self._current_model
                
            except Exception as e:
                print(f"Error getting coder model: {e}")
                raise

    def get_memory_model(self) -> Llama:
        """Get the memory model, ensuring proper cleanup of coder model"""
        with self._lock:
            try:
                if self._model_type == "Memory":
                    return self._current_model
                
                print("Switching to memory model...")
                print(f"Initial CUDA memory: {torch.cuda.memory_allocated()/1024**3:.2f}GB")
                
                # Explicitly unload current model and clean memory
                self._unload_current_model()
                
                print(f"Loading memory model with {self.fast_gpu_layers} GPU layers")
                self._current_model = Llama(
                    model_path=self.fast_model_path,
                    n_ctx=MAX_CONTEXT_TOKENS,
                    n_threads=os.cpu_count(),
                    n_gpu_layers=self.fast_gpu_layers,  # Use calculated layers
                    main_gpu=0,
                    use_mmap=True,
                    use_mlock=False,
                    vocab_only=False,
                    attention_type=2,  # Enable Flash Attention 2
                    dtype='bfloat16'  # Required for Flash Attention 2
                )
                self._model_type = "Memory"
                print(f"Final CUDA memory: {torch.cuda.memory_allocated()/1024**3:.2f}GB")
                return self._current_model
                
            except Exception as e:
                print(f"Error getting memory model: {e}")
                raise

    def _ensure_model_cleanup(self):
        """Ensure proper cleanup of current model"""
        if self._current_model:
            print(f"Cleaning up {self._model_type} model...")
            try:
                del self._current_model
                self._current_model = None
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
                    torch.cuda.synchronize()
                    print("CUDA memory cleared")
            except Exception as e:
                print(f"Error during model cleanup: {e}")

    def get_active_model_name(self) -> str:
        """Get the name of the currently active model"""
        if self._model_type == "Main":
            return "Qwen Coder"
        elif self._model_type == "Memory":
            return "Memory"
        return "No model loaded"

    def cleanup(self):
        """Clean up model resources with proper memory management"""
        with self._lock:
            try:
                if self._current_model:
                    # Force CUDA synchronization before deletion
                    if torch.cuda.is_available():
                        torch.cuda.synchronize()
                    
                    # Proper cleanup sequence
                    self._current_model = None
                    torch.cuda.empty_cache()
                    
                    # Reset state
                    self._model_type = None
                    print("Model cleanup complete")
                    
            except Exception as e:
                print(f"Error during model cleanup: {e}")
            finally:
                # Ensure CUDA cache is cleared
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()

    def __del__(self):
        """Ensure cleanup on deletion"""
        if self._current_model:
            del self._current_model
            self._current_model = None
            if torch.cuda.is_available():
                torch.cuda.empty_cache()

    def _clean_markdown(self, content: str) -> str:
        """Clean markdown content while preserving code blocks"""
        try:
            # Split content into code and non-code segments
            segments = []
            code_block_pattern = r'(```[\s\S]*?```|`[^`]+`)'
            
            # Split by code blocks and process each segment
            parts = re.split(code_block_pattern, content)
            
            for i, part in enumerate(parts):
                if part and (part.startswith('```') or (part.startswith('`') and part.endswith('`'))):
                    # Code block - preserve exactly as is
                    segments.append(part)
                else:
                    # Non-code text - clean normally
                    cleaned = part
                    # Clean only non-code segments
                    cleaned = re.sub(r'\s+', ' ', cleaned)  # Normalize whitespace
                    cleaned = cleaned.strip()
                    segments.append(cleaned)
            
            # Rejoin preserving original code blocks
            return ''.join(segments)
            
        except Exception as e:
            print(f"Error cleaning markdown: {e}")
            return content

class MemoryStore:
    def __init__(self, model_manager=None):
        self.storage_path = Path("conversation_history")
        self.storage_path.mkdir(parents=True, exist_ok=True)
        
        self.messages = {}
        self.model_manager = model_manager  # Just store the reference
        self.personal_info = {'info': {}}
        
        # Initialize files if needed
        for filename, default in [
            ("messages.json", '{}'),
            ("personal_info.json", '{"info": {}}')
        ]:
            path = self.storage_path / filename
            if not path.exists():
                path.write_text(default, encoding='utf-8')
        
        self._load_from_disk()
        
        try:
            self.encoder = tiktoken.get_encoding("cl100k_base")
        except Exception as e:
            print(f"Failed to initialize encoder: {e}")
            self.encoder = None

    def _cleanup_temp_files(self):
        """Clean up temporary files with proper error handling"""
        try:
            # Clean up temp files
            for pattern in ["*.tmp", "*.bak", "*.old"]:
                for temp_file in self.storage_path.glob(pattern):
                    try:
                        if temp_file.is_file():
                            temp_file.unlink()
                            print(f"Cleaned up: {temp_file}")
                    except Exception as e:
                        print(f"Error deleting {temp_file}: {e}")
                        
            # Clean up empty directories
            for dir_path in self.storage_path.glob("**/"):
                try:
                    if dir_path.is_dir() and not any(dir_path.iterdir()):
                        dir_path.rmdir()
                        print(f"Removed empty directory: {dir_path}")
                except Exception as e:
                    print(f"Error cleaning directory {dir_path}: {e}")
                    
        except Exception as e:
            print(f"Error during temp file cleanup: {e}")

    def _load_from_disk(self):
        """Load messages and personal info from disk with better error handling"""
        try:
            messages_file = self.storage_path / "messages.json"
            personal_file = self.storage_path / "personal_info.json"
            
            if messages_file.exists():
                try:
                    with messages_file.open('r', encoding='utf-8') as f:
                        self.messages = json.load(f)
                    print(f"Loaded {len(self.messages)} conversation threads")
                except json.JSONDecodeError as e:
                    print(f"Error decoding messages.json: {e}")
                    self.messages = {}
                except Exception as e:
                    print(f"Error loading messages: {e}")
                    self.messages = {}
            
            if personal_file.exists():
                try:
                    with personal_file.open('r', encoding='utf-8') as f:
                        self.personal_info = json.load(f)
                    print("Loaded personal information")
                except json.JSONDecodeError as e:
                    print(f"Error decoding personal_info.json: {e}")
                    self.personal_info = {'info': {}}
                except Exception as e:
                    print(f"Error loading personal info: {e}")
                    self.personal_info = {'info': {}}
                
        except Exception as e:
            print(f"Error in _load_from_disk: {e}")
            self.messages = {}
            self.personal_info = {'info': {}}

    def _save_to_disk(self) -> bool:
        """Save messages and personal info with proper error handling"""
        try:
            # Ensure directory exists
            self.storage_path.mkdir(parents=True, exist_ok=True)
            
            # Save messages
            messages_file = self.storage_path / "messages.json"
            temp_messages = messages_file.with_suffix('.tmp')
            
            try:
                with temp_messages.open('w', encoding='utf-8') as f:
                    json.dump(self.messages, f, indent=2, default=str)
                temp_messages.replace(messages_file)
                print("Messages saved successfully")
            except Exception as e:
                print(f"Error saving messages: {e}")
                if temp_messages.exists():
                    temp_messages.unlink()
                return False
            
            # Save personal info
            personal_file = self.storage_path / "personal_info.json"
            temp_personal = personal_file.with_suffix('.tmp')
            
            try:
                with temp_personal.open('w', encoding='utf-8') as f:
                    json.dump(self.personal_info, f, indent=2, default=str)
                temp_personal.replace(personal_file)
                print("Personal info saved successfully")
            except Exception as e:
                print(f"Error saving personal info: {e}")
                if temp_personal.exists():
                    temp_personal.unlink()
                return False
            
            return True
            
        except Exception as e:
            print(f"Error in _save_to_disk: {e}")
            return False

    def _analyze_with_model(self, prompt: str, max_tokens: int = 10) -> str:
        """Use memory model for analysis with better token management"""
        try:
            print("\n=== MODEL ANALYSIS ===")
            print(f"Max tokens: {max_tokens}")
            
            if not self.memory_model:
                print("Getting new memory model...")
                try:
                    self.memory_model = self.model_manager.get_memory_model()
                    self.current_tokens = 0
                except Exception as e:
                    print(f"Error getting memory model: {str(e)}")
                    return ""
            
            # Token estimation
            if self.encoder:
                prompt_tokens = len(self.encoder.encode(prompt))
                print(f"Estimated prompt tokens: {prompt_tokens}")
            else:
                words = prompt.split()
                prompt_tokens = sum(len(word) // 2 for word in words)
                print(f"Fallback token estimation: {prompt_tokens}")
            
            # Check token threshold
            if self.current_tokens + prompt_tokens > self.token_threshold - max_tokens:
                print(f"\nToken threshold warning:")
                print(f"Current tokens: {self.current_tokens}")
                print(f"Threshold: {self.token_threshold}")
                print("Refreshing model to prevent context overflow")
                self.cleanup_model()
                self.memory_model = self.model_manager.get_memory_model()
                self.current_tokens = 0
            
            print("\n=== GENERATING COMPLETION ===")
            result = self.memory_model.create_completion(
                prompt,
                max_tokens=max_tokens,
                temperature=0.1,
                top_p=0.1,
                stream=False
            )
            
            # Token counting
            completion = result['choices'][0]['text']
            if self.encoder:
                completion_tokens = len(self.encoder.encode(completion))
            else:
                words = completion.split()
                completion_tokens = sum(len(word) // 2 for word in words)
            
            self.current_tokens += prompt_tokens + completion_tokens
            print(f"\nCompletion tokens: {completion_tokens}")
            print(f"New total tokens: {self.current_tokens}")
            
            return completion.strip()
            
        except Exception as e:
            print(f"\n=== ERROR ===")
            print(f"Error in model analysis: {str(e)}")
            self.cleanup_model()  # Cleanup on error
            return ""

    def analyze_query(self, query: str) -> str:
        """Analyze query type with model validation"""
        try:
            print("\n=== QUERY ANALYSIS ===")
            print(f"Input query: {query[:100]}...")
            print(f"Current model: {self.model_manager.get_active_model_name()}")
            
            # Validate model state before using
            if not self._validate_model_state():
                print("Model validation failed, using fallback analysis")
                return "chat"  # Safe fallback
            
            # Quick check for code indicators
            code_indicators = ['code', 'script', 'function', 'optimize', 'programming']
            if any(indicator in query.lower() for indicator in code_indicators):
                print("Code indicators found in query")
                return "code"
            
            # Create analysis prompt
            prompt = "<|im_start|>system\n"
            prompt += "Analyze if this is a code-related query. Respond with 'code' or 'chat'.\n"
            prompt += "<|im_end|>\n"
            prompt += f"<|im_start|>user\n{query}<|im_end|>\n"
            prompt += "<|im_start|>assistant\n"
            
            print("\n=== MODEL INPUT ===")
            print(f"Analysis prompt:\n{prompt}")
            
            # Use shared model instance
            response = self._analyze_with_model(prompt)
            print(f"\n=== MODEL OUTPUT ===")
            print(f"Raw response: {response}")
            print(f"Final analysis: {'code' if 'code' in response.lower() else 'chat'}")
            
            return "code" if "code" in response.lower() else "chat"
            
        except Exception as e:
            print(f"\n=== ERROR ===")
            print(f"Error in query analysis: {str(e)}")
            return "chat"

    def _get_current_identity(self) -> str:
        """Get the current primary identity"""
        try:
            if 'identity' in self.personal_info['info']:
                identity_entries = self.personal_info['info']['identity']
                if identity_entries:
                    # Get most recent identity entry
                    latest = max(identity_entries, key=lambda x: x['timestamp'])
                    return latest['name']  # We store it as 'name' not 'person'
            return 'Unknown'
        except Exception as e:
            print(f"Error getting current identity: {e}")
            return 'Unknown'

    def _extract_personal_info(self, query: str) -> Dict:
        try:
            print("\n=== MEMORY DEBUG ===")
            print(f"Input query: {query}")
            print(f"Current personal_info state: {json.dumps(self.personal_info, indent=2)}")
            
            # Use double curly braces to escape JSON examples in the prompt
            prompt = """<|im_start|>system
You are an AI that extracts personal information from text. Return ONLY valid JSON.

For user identity statements like:
"My name is John"
Return: {{"identity":{{"name":"John"}}}}

For relationship statements with details like:
"My wife is Rose or Rosemary and she is 34"
Return: {{"relationships":[{{"type":"wife","person":"Rose","details":{{"age":34,"alias":"Rosemary"}}}}]}}

For multiple relationships like:
"My parents are Cheryl and Eric"
Return: {{"relationships":[{{"type":"mother","person":"Cheryl"}},{{"type":"father","person":"Eric"}}]}}

Return ONLY the JSON object, no additional text.
<|im_end|>
<|im_start|>user
{0}
<|im_end|>
<|im_start|>assistant
""".format(query)

            print("\n=== MODEL INPUT ===")
            print(f"Extraction prompt:\n{prompt}")
            
            result = self.memory_model.create_completion(
                prompt,
                max_tokens=500,
                temperature=0.1,
                top_p=0.05,
                stream=False
            )
            
            print("\n=== MODEL OUTPUT ===")
            print(f"Raw model result: {json.dumps(result, indent=2)}")
            
            # Get and clean response
            response = result['choices'][0]['text'].strip()
            print(f"Extracted response: {response}")
            
            # Ensure we have valid JSON
            response = re.sub(r'^[^{]*({.*})[^}]*$', r'\1', response)
            response = re.sub(r'\s+', '', response)
            print(f"Cleaned response: {response}")
            
            try:
                info = json.loads(response)
                print("\n=== PARSED INFO ===")
                print(f"Parsed JSON: {json.dumps(info, indent=2)}")
                
                # Initialize storage with correct structure
                if 'info' not in self.personal_info:
                    self.personal_info['info'] = {}
                if 'identity' not in self.personal_info['info']:
                    self.personal_info['info']['identity'] = []
                if 'relationships' not in self.personal_info['info']:
                    self.personal_info['info']['relationships'] = []
                
                print("\n=== STORAGE UPDATES ===")
                
                # Store identity
                if 'identity' in info:
                    identity_entry = {
                        'type': 'identity',
                        'name': info['identity']['name'],
                        'timestamp': datetime.now().isoformat()
                    }
                    self.personal_info['info']['identity'].append(identity_entry)
                    print(f"Added identity: {json.dumps(identity_entry, indent=2)}")
                
                # Store relationships as list entries
                if 'relationships' in info:
                    for rel in info['relationships']:
                        rel['timestamp'] = datetime.now().isoformat()
                        self.personal_info['info']['relationships'].append(rel)
                        print(f"Added relationship: {json.dumps(rel, indent=2)}")
                
                # Save changes
                success = self._save_to_disk()
                print(f"\nSave result: {success}")
                
                if success:
                    print("\n=== VERIFICATION ===")
                    print(f"Final personal_info state: {json.dumps(self.personal_info, indent=2)}")
                    return info
                else:
                    print("\n=== ERROR ===")
                    print("Failed to save personal info to disk")
                    return {}
                
            except json.JSONDecodeError as e:
                print(f"JSON decode error: {e}")
                return {}
                
        except Exception as e:
            print("\n=== ERROR ===")
            print(f"Error extracting personal info: {str(e)}")
            print("Stack trace:", traceback.format_exc())
            return {}

    def _update_identity(self, identity_info: Dict):
        """Update identity information"""
        if 'identity' not in self.personal_info['info']:
            self.personal_info['info']['identity'] = []
        
        if identity_info.get('is_speaking'):
            self.personal_info['info']['identity'].append({
                'value': identity_info,
                'timestamp': datetime.now().isoformat(),
                'confidence': 'explicit'
            })
            self._save_to_disk()

    def _update_relationships(self, relationships: Dict):
        """Update relationships maintaining bidirectional connections"""
        if 'relationships' not in self.personal_info['info']:
            self.personal_info['info']['relationships'] = {}
        
        for rel_type, details in relationships.items():
            # Store forward relationship
            if rel_type not in self.personal_info['info']['relationships']:
                self.personal_info['info']['relationships'][rel_type] = []
            
            self.personal_info['info']['relationships'][rel_type].append({
                'value': details,
                'timestamp': datetime.now().isoformat(),
                'confidence': 'explicit'
            })
            
            # Store bidirectional relationship if present
            if 'bidirectional' in details:
                bidir = details['bidirectional']
                bidir_type = bidir['type']
                
                if bidir_type not in self.personal_info['info']['relationships']:
                    self.personal_info['info']['relationships'][bidir_type] = []
                
                self.personal_info['info']['relationships'][bidir_type].append({
                    'value': {
                        'person': bidir['person'],
                        'details': {},
                        'bidirectional': {
                            'type': rel_type,
                            'person': details['person']
                        }
                    },
                    'timestamp': datetime.now().isoformat(),
                    'confidence': 'implicit'
                })
        
        self._save_to_disk()

    def get_context(self, thread_id: str, current_message: str = None) -> str:
        """Get conversation context as a single string"""
        try:
            context_parts = []
            
            # Get identity and relationships context
            identity = self._get_current_identity()
            if identity != 'Unknown':
                # Add relationships if available
                if 'relationships' in self.personal_info['info']:
                    relationships = [
                        rel for rel in self.personal_info['info']['relationships']
                        if not rel.get('type') == 'identity'
                    ]
                    
                    if relationships:
                        # Format relationships in tree structure
                        rel_tree = [f"# Family Tree for {identity}"]
                        for rel in relationships:
                            rel_str = self._format_relationship(rel)
                            if rel_str:
                                # Add proper indentation for tree structure
                                rel_tree.append(f"    {rel_str}")
                    
                        if len(rel_tree) > 1:  # Only add if we have relationships
                            context_parts.append(
                                f"<|im_start|>system\n"
                                f"{chr(10).join(rel_tree)}\n"
                                f"<|im_end|>"
                            )
            
            # Add message history
            if thread_id in self.messages:
                messages = self.messages[thread_id][-5:]  # Get last 5 messages
                for msg in messages:
                    role = msg.get('role', '')
                    content = msg.get('content', '')
                    if content:
                        if role == 'user':
                            context_parts.append(f"<|im_start|>user\n{content}<|im_end|>")
                        elif role == 'assistant':
                            context_parts.append(f"<|im_start|>assistant\n{content}<|im_end|>")
            
            # Join all context parts with newlines
            return "\n".join(context_parts)
            
        except Exception as e:
            print(f"Error getting context: {e}")
            return ""

    def _get_relevant_relationships(self, query: str) -> Dict:
        """Get relationships relevant to current query"""
        try:
            # Create relevance checking prompt
            prompt = """<|im_start|>system
Determine which relationships are relevant to this query.
Return JSON array of relationship types that should be included in context.
<|im_end|>
<|im_start|>user
Known relationships:
{relationships}

Query: {query}
<|im_end|>
<|im_start|>assistant
"""
            result = self.memory_model.create_completion(
                prompt.format(
                    relationships=self._format_known_relationships(),
                    query=query
                ),
                max_tokens=100,
                temperature=0.1,
                stream=False
            )
            
            relevant_types = json.loads(result['choices'][0]['text'])
            
            # Filter relationships
            relevant = {}
            for rel_type in relevant_types:
                if rel_type in self.personal_info['info']:
                    relevant[rel_type] = self.personal_info['info'][rel_type]
            
            return relevant
            
        except Exception as e:
            print(f"Error getting relevant relationships: {e}")
            return {}

    def _get_relevant_message_window(
        self,
        messages: List[Dict],
        current_query: str,
        max_messages: int = 5
    ) -> List[Dict]:
        """Get relevant message window based on query"""
        try:
            # Sort by timestamp
            sorted_msgs = sorted(messages, key=lambda x: x['timestamp'])
            
            # If few messages, return all
            if len(sorted_msgs) <= max_messages:
                return sorted_msgs
            
            # Create relevance scoring prompt
            prompt = """<|im_start|>system
Score how relevant each message is to the current query (0-10).
Return only the score number.
<|im_end|>
<|im_start|>user
Query: {query}
Message: {message}
<|im_end|>
<|im_start|>assistant
"""
            
            # Score messages
            scored_messages = []
            for msg in sorted_msgs[-10:]:  # Only score recent messages
                result = self.memory_model.create_completion(
                    prompt.format(
                        query=current_query,
                        message=msg['content']
                    ),
                    max_tokens=10,
                    temperature=0.1,
                    stream=False
                )
                
                try:
                    score = float(result['choices'][0]['text'].strip())
                    scored_messages.append((score, msg))
                except ValueError:
                    scored_messages.append((0, msg))
            
            # Sort by score and get top messages
            scored_messages.sort(key=lambda x: (-x[0], x[1]['timestamp']))
            return [msg for _, msg in scored_messages[:max_messages]]
            
        except Exception as e:
            print(f"Error getting relevant messages: {e}")
            return sorted_msgs[-max_messages:]  # Fallback to recent messages

    def add_message(self, thread_id: str, role: str, content: str, timestamp: Optional[str] = None) -> None:
        """Add message with proper timestamp and info extraction"""
        try:
            if not content or not content.strip():
                print("Skipping empty message")
                return
            
            if role not in {'user', 'assistant', 'system'}:
                print(f"Invalid role: {role}")
                return
            
            thread_id = self._validate_thread_id(thread_id)
            
            # Use provided timestamp or create new one
            msg_timestamp = timestamp or datetime.now().isoformat()
            
            # Clean content and extract info from user messages
            cleaned_content = self._clean_markdown(content)
            if role == 'user':
                personal_info = self._extract_personal_info(cleaned_content)
                if personal_info:
                    print(f"Extracted personal info: {json.dumps(personal_info, indent=2)}")
                    # Update identity and relationships
                    if 'identity' in personal_info:
                        self._update_identity(personal_info['identity'])
                    if 'relationships' in personal_info:
                        self._update_relationships(personal_info['relationships'])
            
            # Create message with timestamp
            message = {
                'role': role,
                'content': cleaned_content,
                'timestamp': msg_timestamp,
                'importance': 0.5  # Default importance
            }
            
            if thread_id not in self.messages:
                self.messages[thread_id] = []
            
            self.messages[thread_id].append(message)
            
            # Save after each message to ensure persistence
            self._save_to_disk()
            
            print(f"Added {role} message to thread {thread_id}")
            if role == 'user':
                print(f"Current identity: {self._get_current_identity()}")
                print(f"Known relationships: {self._format_known_relationships()}")
            
        except Exception as e:
            print(f"Error adding message: {str(e)}")

    def _is_code_message(self, content: str) -> bool:
        """Check if message contains code blocks"""
        return '```' in content or any(
            keyword in content.lower() for keyword in [
                'def ', 'class ', 'function', 'return',
                'import ', 'from ', '#include'
            ]
        )

    def _is_code_query(self, content: str, model: Optional[Llama] = None) -> bool:
        """Analyze content using provided or new model instance"""
        try:
            # Use provided model or get new one
            if model is None:
                model = self.model_manager.get_memory_model()
            
            # Calculate initial chunk size (10% of content)
            chunk_size = max(100, len(content) // 10)
            chunks = []
            
            # Split content into chunks
            for i in range(0, len(content), chunk_size):
                chunks.append(content[i:i + chunk_size])
            
            print(f"\n=== Progressive Content Analysis ===")
            print(f"Content length: {len(content)} chars")
            print(f"Split into {len(chunks)} chunks of ~{chunk_size} chars")
            
            # Analyze first chunk
            first_chunk = chunks[0]
            
            # Create focused prompt for code detection
            prompt = """<|im_start|>system
Analyze if this content is code-related. If uncertain, respond 'more'. Otherwise respond only 'code' or 'not_code'.
<|im_end|>
<|im_start|>user
{content}
<|im_end|>
<|im_start|>assistant
"""
            # First pass with initial chunk
            result = model.create_completion(
                prompt.format(content=first_chunk),
                max_tokens=5,
                temperature=0.1,
                top_p=0.1,
                stream=False
            )
            
            response = result['choices'][0]['text'].strip().lower()
            print(f"Initial chunk analysis: {response}")
            
            # If model is certain, return result (keep model loaded for next query)
            if response in ['code', 'not_code']:
                return response == 'code'
            
            # If model needs more context, analyze additional chunks with same model instance
            for i, chunk in enumerate(chunks[1:], 1):
                print(f"\nAnalyzing chunk {i + 1}/{len(chunks)}")
                
                result = model.create_completion(
                    prompt.format(content=chunk),
                    max_tokens=5,
                    temperature=0.1,
                    top_p=0.1,
                    stream=False
                )
                
                response = result['choices'][0]['text'].strip().lower()
                print(f"Chunk {i + 1} analysis: {response}")
                
                # If model is certain, return result
                if response in ['code', 'not_code']:
                    return response == 'code'
                
                # Limit number of chunks analyzed
                if i >= 4:  # Only analyze up to 5 chunks total
                    print("Reached maximum chunks limit")
                    break
            
            # Make final decision based on last response
            print("Making final decision based on analyzed chunks")
            return 'code' in response
            
        except Exception as e:
            print(f"Model-based code detection failed: {str(e)}")
            # Model cleanup happens in ModelManager
            raise

    def _format_personal_context(self) -> str:
        """Format personal info into natural context"""
        if not self.personal_info['info']:
            return ""
            
        context_parts = []
        
        # Format name
        if 'user_name' in self.personal_info['info']:
            name_entries = self.personal_info['info']['user_name']
            if name_entries:
                latest_name = max(name_entries, key=lambda x: x['timestamp'])
                context_parts.append(f"Your name is {latest_name['value']}")
        
        # Format attributes
        if 'user_attributes' in self.personal_info['info']:
            attr_entries = self.personal_info['info']['user_attributes']
            if attr_entries:
                latest_attrs = max(attr_entries, key=lambda x: x['timestamp'])
                if isinstance(latest_attrs['value'], list):
                    for attr_dict in latest_attrs['value']:
                        for key, value in attr_dict.items():
                            if key != 'timestamp' and key != 'context':
                                context_parts.append(f"Your {key.replace('_', ' ')} is {value}")
        
        # Format relationships
        if 'relationships' in self.personal_info['info']:
            rel_entries = self.personal_info['info']['relationships']
            if rel_entries:
                latest_rels = max(rel_entries, key=lambda x: x['timestamp'])
                if isinstance(latest_rels['value'], list):
                    for rel_dict in latest_rels['value']:
                        for key, value in rel_dict.items():
                            if key != 'timestamp' and key != 'context':
                                context_parts.append(f"Your {key.replace('_', ' ')} is {value}")
        
        # Add any additional personal details
        for key, values in self.personal_info['info'].items():
            if key not in ['user_name', 'user_attributes', 'relationships'] and values:
                if isinstance(values, list):
                    latest = max(values, key=lambda x: x['timestamp'])
                    if isinstance(latest['value'], str):
                        context_parts.append(f"Your {key.replace('_', ' ')}: {latest['value']}")
                    elif isinstance(latest['value'], list):
                        for item in latest['value']:
                            if isinstance(item, dict):
                                for k, v in item.items():
                                    if k != 'timestamp' and k != 'context':
                                        context_parts.append(f"Your {k.replace('_', ' ')}: {v}")
        
        return "\n".join(context_parts)

    def _format_for_display(self, content: str) -> str:
        """Format message content for display"""
        lines = content.split('\n')
        formatted = []
        
        for line in lines:
            # Format headers
            if re.match(r'^[A-Z][^.!?]*:$', line):
                formatted.append(f"**{line}**")
            else:
                formatted.append(line)
        
        return '\n'.join(formatted)

    def clear_thread(self, thread_id: str) -> bool:
        """Clear a specific conversation thread"""
        try:
            thread_id = self._validate_thread_id(thread_id)
            if thread_id in self.messages:
                del self.messages[thread_id]
            return True
        except Exception as e:
            print(f"Error clearing thread {thread_id}: {str(e)}")
            return False

    def clear_all(self) -> bool:
        """Clear all conversation threads"""
        try:
            self.messages = {}
            self.memory_model = None  # This line is causing the error
            return True
        except Exception as e:
            print(f"Error clearing all threads: {str(e)}")
            return False

    def get_thread_ids(self) -> List[str]:
        """Get all thread IDs"""
        return list(self.messages.keys())

    def _get_personal_context(self) -> str:
        """Get personal context - simplified to return empty for now"""
        return ""

    def get_cached_code_response(self, query: str) -> Optional[str]:
        """Stub for compatibility - no caching in simplified version"""
        return None

    def get_token_stats(self, thread_id: str) -> Dict:
        """Get token statistics for a thread"""
        messages = self.messages.get(thread_id, [])
        if not self.encoder:
            return {'message_count': len(messages), 'token_count': 0}
            
        return {
            'message_count': len(messages),
            'token_count': sum(len(self.encoder.encode(msg['content'])) 
                             for msg in messages)
        }

    def truncate_text(self, text: str, use_chars: bool = False) -> str:
        """Truncate text for analysis using tokens or characters"""
        if not use_chars and self.encoder:
            try:
                tokens = self.encoder.encode(text)
                if len(tokens) > MAX_ANALYSIS_TOKENS:
                    truncate_length = max(MIN_ANALYSIS_TOKENS, 
                                        int(len(tokens) * ANALYSIS_TRUNCATE_PERCENT))
                    return self.encoder.decode(tokens[:truncate_length])
                return text
            except Exception as e:
                print(f"Token truncation failed: {e}")
                use_chars = True
        
        # Fallback to character-based truncation
        if use_chars:
            return text[:FALLBACK_CHAR_LIMIT]
        return text

    def search_memories(self, thread_id: str, query: str) -> List[Dict]:
        """Search through stored memories for relevant information"""
        if thread_id not in self.messages:
            return []
            
        # For memory queries, just return all messages - let the model naturally process them
        return self.messages[thread_id]

    def __del__(self):
        """Cleanup when object is destroyed"""
        try:
            # Clean up temp files
            self._cleanup_temp_files()
            
            # Clean up model resources
            if hasattr(self, 'memory_model') and self.memory_model:
                try:
                    del self.memory_model
                    self.memory_model = None
                except:
                    pass
                
            # Clean up model manager
            if hasattr(self, 'model_manager') and self.model_manager:
                try:
                    self.model_manager.cleanup()
                except:
                    pass
                
            # Clean up encoder
            if hasattr(self, 'encoder'):
                try:
                    del self.encoder
                except:
                    pass
                
        except Exception as e:
            print(f"Error during cleanup: {e}")

    def analyze_messages(self, thread_id: str, current_query: str) -> List[Dict]:
        """Analyze messages for relevance using a single model instance"""
        try:
            # Load model once for all analysis
            model = self.model_manager.get_memory_model()
            
            # Process current query first
            is_code = self._is_code_query(current_query, model)
            print(f"\nMessage type: {'code' if is_code else 'general'}")
            
            # Get thread messages
            messages = self.messages.get(thread_id, [])
            if not messages:
                return []
            
            relevant_messages = []
            for msg in messages:
                # Reuse same model instance for each message
                msg_is_code = self._is_code_query(msg['content'], model)
                if msg_is_code == is_code:
                    relevant_messages.append(msg)
                
            return relevant_messages[-MAX_MEMORIES:]
            
        except Exception as e:
            print(f"Error analyzing messages: {str(e)}")
            return []

    def get_model_response(self, thread_id: str, message: str) -> Iterator[str]:
        """Get streaming response with thread safety"""
        model = None
        try:
            with self._lock:  # Add thread lock
                if not message.strip():
                    yield "Error: Empty message"
                    return
                
                thread_id = self._validate_thread_id(thread_id)
                
                context = self.get_context(thread_id, message)
                if not context:
                    yield "Error: Failed to get conversation context"
                    return

                try:
                    model = self.model_manager.get_main_model()
                except Exception as e:
                    print(f"Error getting model: {e}")
                    yield f"Error: Failed to load model - {str(e)}"
                    return

                prompt = self._format_prompt(context, message)
                
                try:
                    response = model.create_completion(
                        prompt,
                        max_tokens=2048,
                        temperature=0.7,
                        top_p=0.95,
                        stream=True
                    )
                    
                    for chunk in response:
                        if chunk and 'choices' in chunk:
                            text = chunk['choices'][0].get('text', '')
                            if text:
                                yield text
                                
                except Exception as e:
                    print(f"Error during generation: {e}")
                    yield f"Error during generation: {str(e)}"
                    
        except Exception as e:
            print(f"Error in get_model_response: {str(e)}")
            yield f"Error: {str(e)}"
        finally:
            # Ensure model is cleaned up
            if model:
                try:
                    del model
                    if torch.cuda.is_available():
                        torch.cuda.empty_cache()
                except:
                    pass

    def cleanup_model(self):
        """Reset model and token count"""
        try:
            if self.memory_model:
                self.memory_model = self.model_manager.get_memory_model()
                self.current_tokens = 0
                print("Memory model refreshed and token count reset")
        except Exception as e:
            print(f"Error cleaning up model: {str(e)}")

    def _format_prompt(self, context: List[Dict], message: str) -> str:
        """Format context and message into a proper prompt"""
        try:
            prompt = ""
            for item in context:
                if isinstance(item, dict) and 'role' in item and 'content' in item:
                    prompt += f"<|im_start|>{item['role']}\n{item['content']}<|im_end|>\n"
            
            prompt += f"<|im_start|>user\n{message}<|im_end|>\n"
            prompt += "<|im_start|>assistant\n"
            return prompt
        except Exception as e:
            print(f"Error formatting prompt: {str(e)}")
            return f"<|im_start|>user\n{message}<|im_end|>\n<|im_start|>assistant\n"

    def _validate_model_state(self) -> bool:
        """Validate model state and reinitialize if needed"""
        try:
            if not self.memory_model:
                print("Model not initialized, attempting to load")
                self.memory_model = self.model_manager.get_memory_model()
                self.current_tokens = 0
                return bool(self.memory_model)
            
            try:
                # Test model with simple prompt
                test_prompt = "<|im_start|>user\ntest<|im_end|>\n<|im_start|>assistant\n"
                result = self.memory_model.create_completion(
                    test_prompt,
                    max_tokens=1,
                    temperature=0.1,
                    stream=False
                )
                return bool(result and 'choices' in result)
            except Exception as e:
                print(f"Model test failed: {e}")
                # Try to reinitialize model
                self.memory_model = self.model_manager.get_memory_model()
                return bool(self.memory_model)
            
        except Exception as e:
            print(f"Model validation failed: {str(e)}")
            return False

    def _validate_message(self, message: Dict) -> bool:
        """Validate message structure"""
        required_fields = {'role', 'content', 'timestamp'}
        return (
            isinstance(message, dict) and
            all(field in message for field in required_fields) and
            isinstance(message['content'], str) and
            message['content'].strip() and
            message['role'] in {'user', 'assistant', 'system'}
        )

    def _validate_thread_id(self, thread_id: str) -> str:
        """Validate and normalize thread ID"""
        if not thread_id:
            return 'default'
        
        # Remove invalid characters
        thread_id = re.sub(r'[^a-zA-Z0-9_-]', '', thread_id)
        
        # Ensure reasonable length
        if len(thread_id) > 64:
            thread_id = thread_id[:64]
        
        return thread_id or 'default'

    def _format_known_relationships(self) -> str:
        """Format known relationships into a readable string"""
        try:
            if not self.personal_info['info'].get('relationships'):
                return "No known relationships"
            
            relationships = []
            identity = self._get_current_identity()
            
            for rel_type, entries in self.personal_info['info']['relationships'].items():
                if entries:
                    # Get most recent entry
                    latest = max(entries, key=lambda x: x['timestamp'])
                    details = latest['value']
                    
                    # Format relationship details
                    rel_str = f"{rel_type}: {details['person']}"
                    if 'details' in details and details['details']:
                        extra = []
                        if 'age' in details['details']:
                            extra.append(f"age {details['details']['age']}")
                        if 'alias' in details['details']:
                            extra.append(f"also known as {details['details']['alias']}")
                        if extra:
                            rel_str += f" ({', '.join(extra)})"
                    
                    relationships.append(rel_str)
            
            return "\n".join(relationships)
            
        except Exception as e:
            print(f"Error formatting relationships: {e}")
            return "Error retrieving relationships"

    def _format_relationship(self, rel: Dict) -> str:
        """Helper to format a relationship entry in tree structure"""
        try:
            # Start with indentation for tree structure
            rel_str = "└── "  # Use tree branch character
            
            if 'type' in rel:
                rel_str += f"{rel['type']}: "
            if 'person' in rel:
                rel_str += rel['person']
            
            # Add details in parentheses if present
            if 'details' in rel:
                details = []
                if 'age' in rel['details']:
                    details.append(f"age {rel['details']['age']}")
                if 'alias' in rel['details']:
                    details.append(f"also known as {rel['details']['alias']}")
                if details:
                    rel_str += f" ({', '.join(details)})"
                
            return rel_str
        except Exception as e:
            print(f"Error formatting relationship: {e}")
            return ""

    def _clean_markdown(self, text):
        """Clean markdown formatting from text for better context handling"""
        # Remove code blocks
        text = re.sub(r'```[\s\S]*?```', '', text)
        # Remove markdown links
        text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
        # Remove other markdown formatting
        text = re.sub(r'[*_`#]', '', text)
        return text.strip()

