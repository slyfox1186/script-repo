import json
import os
import threading
import tiktoken
import torch
from datetime import datetime
from llama_cpp import Llama
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import re

# Configuration settings
CODER_GPU_LAYERS = 54       # Reduced from 45 to save VRAM
FAST_GPU_LAYERS = 37        # Reduced from 32 to save VRAM

# Memory settings
MAX_MEMORIES = 50           # Max messages to keep per thread
MAX_CONTEXT_TOKENS = 16384  # Model's context window
MAX_ANALYSIS_TOKENS = 50
MIN_ANALYSIS_TOKENS = 5
ANALYSIS_TRUNCATE_PERCENT = 0.1  # 10%
FALLBACK_CHAR_LIMIT = 100

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
        self._memory_model = None
        self._main_model = None
        self._active_model = None
        
        # Model paths
        self.coder_model_path = "./models/Qwen2.5-Coder-32B-Instruct-Q5_K_L.gguf"
        self.fast_model_path = "./models/Qwen2.5-3B-Instruct-Q6_K_L.gguf"
        
        # Better VRAM management
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            torch.cuda.set_per_process_memory_fraction(0.70)  # Reduced from 0.75

    def get_active_model_name(self) -> str:
        """Get the name of the currently active model"""
        if self._main_model:
            return "Qwen Coder"
        elif self._memory_model:
            return "Memory"
        return "No model loaded"

    def get_memory_model(self):
        """Get the memory model"""
        with self._lock:
            # Clean up main model if it exists
            if self._main_model:
                del self._main_model
                self._main_model = None
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
            
            self._active_model = "Memory"
            # Load memory model if needed
            if not self._memory_model:
                self._memory_model = Llama(
                    model_path=self.fast_model_path,
                    n_ctx=MAX_CONTEXT_TOKENS,
                    n_gpu_layers=FAST_GPU_LAYERS,
                    main_gpu=0,
                    offload_kqv=True  # Offload key/value cache to CPU
                )
            return self._memory_model

    def get_main_model(self):
        """Get the main model"""
        with self._lock:
            # Clean up memory model if it exists
            if self._memory_model:
                del self._memory_model
                self._memory_model = None
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
            
            self._active_model = "Qwen Coder"
            # Load main model if needed
            if not self._main_model:
                self._main_model = Llama(
                    model_path=self.coder_model_path,
                    n_ctx=MAX_CONTEXT_TOKENS,
                    n_gpu_layers=CODER_GPU_LAYERS,
                    main_gpu=0,
                    offload_kqv=True  # Offload key/value cache to CPU
                )
            return self._main_model

    def cleanup(self):
        """Clean up model resources"""
        with self._lock:
            if self._memory_model:
                del self._memory_model
                self._memory_model = None
            if self._main_model:
                del self._main_model
                self._main_model = None
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            self._active_model = None

class MemoryStore:
    def __init__(self, model_manager=None):
        self.storage_path = Path("conversation_history")
        self.storage_path.mkdir(exist_ok=True)
        self.messages = {}
        self.model_manager = model_manager
        self.personal_info = {'info': {}}
        self._cleanup_temp_files()
        
        # Load existing messages from disk
        self._load_from_disk()
        
        try:
            self.encoder = tiktoken.get_encoding("cl100k_base")
        except Exception as e:
            print(f"Failed to initialize encoder: {e}")
            self.encoder = None

    def _cleanup_temp_files(self):
        """Clean up any temporary files from previous runs"""
        try:
            for temp_file in self.storage_path.glob("*.tmp"):
                try:
                    temp_file.unlink()
                except Exception as e:
                    print(f"Error deleting temp file {temp_file}: {e}")
        except Exception as e:
            print(f"Error during temp file cleanup: {e}")

    def _load_from_disk(self):
        """Load messages and personal info from disk with error handling"""
        try:
            # Load messages.json
            messages_file = self.storage_path / "messages.json"
            if messages_file.exists():
                try:
                    with messages_file.open('r', encoding='utf-8') as f:
                        self.messages = json.load(f)
                        print(f"Loaded {len(self.messages)} threads from disk")
                except Exception as e:
                    print(f"Error loading messages.json: {e}")
                    self.messages = {}
            
            # Load personal_info.json
            personal_file = self.storage_path / "personal_info.json"
            if personal_file.exists():
                try:
                    with personal_file.open('r', encoding='utf-8') as f:
                        self.personal_info = json.load(f)
                except Exception as e:
                    print(f"Error loading personal_info.json: {e}")
                    self.personal_info = {'info': {}}
                    
        except Exception as e:
            print(f"Error in _load_from_disk: {e}")
            self.messages = {}
            self.personal_info = {'info': {}}

    def _save_to_disk(self):
        """Save messages and personal info to disk with error handling"""
        try:
            # Ensure directory exists
            self.storage_path.mkdir(exist_ok=True)
            
            # Save messages with atomic write using temporary file
            messages_temp = self.storage_path / "messages.json.tmp"
            messages_final = self.storage_path / "messages.json"
            
            with messages_temp.open('w', encoding='utf-8') as f:
                json.dump(self.messages, f, indent=2, ensure_ascii=False)
            messages_temp.replace(messages_final)
            
            # Save personal info with atomic write
            personal_temp = self.storage_path / "personal_info.json.tmp"
            personal_final = self.storage_path / "personal_info.json"
            
            with personal_temp.open('w', encoding='utf-8') as f:
                json.dump(self.personal_info, f, indent=2, ensure_ascii=False)
            personal_temp.replace(personal_final)
            
            print(f"Saved {len(self.messages)} threads to disk")
            
        except Exception as e:
            print(f"Error in _save_to_disk: {e}")
            # Clean up temp files if they exist
            self._cleanup_temp_files()

    def analyze_query(self, query: str) -> str:
        """Analyze query type with truncated text for efficiency"""
        # Only truncate the query for analysis, not storage
        analysis_text = query
        if self.encoder:
            try:
                tokens = self.encoder.encode(query)
                if len(tokens) > MAX_ANALYSIS_TOKENS:
                    truncate_length = max(MIN_ANALYSIS_TOKENS, 
                                        int(len(tokens) * ANALYSIS_TRUNCATE_PERCENT))
                    analysis_text = self.encoder.decode(tokens[:truncate_length])
            except Exception as e:
                print(f"Token analysis failed: {e}")
                analysis_text = query[:FALLBACK_CHAR_LIMIT]
        
        analysis_prompt = (
            "<|im_start|>system\n"
            "Rules:\n"
            "You are an expert analyzer of user queries and return ONLY one of the approved single words in your reponse:\n\n"
            "Approved Word List:\n"
            "'personal' (for queries about user's personal info like name, family)\n"
            "'code' (for programming/coding related queries)\n"
            "'clear' (for requests to clear conversation)\n"
            "'memory' (for queries about past conversations or stored information)\n"
            "'chat' (for general conversation)\n\n"
            "Examples:\n"
            "- 'What did I say earlier about X?' -> 'memory'\n"
            "- 'Show me our previous conversation' -> 'memory'\n"
            "- 'What was my last question?' -> 'memory'\n"
            "Return ONLY one of the single words allowed and nothing else.\n"
            "<|im_end|>\n"
            "<|im_start|>user\n"
            f"Analyze this query: {analysis_text}\n"
            "<|im_end|>\n"
            "<|im_start|>assistant\n"
        )
        
        try:
            model = self.model_manager.get_memory_model()
            result = model.create_completion(
                analysis_prompt,
                max_tokens=1,
                temperature=0.1,
                top_p=0.05,
                top_k=2,
                stream=False
            )
            query_type = result['choices'][0]['text'].strip().lower()
            
            if query_type == 'personal':
                # Extract personal info
                info = self._extract_personal_info(query)
                if info:
                    self.personal_info['info'].update(info)
                    self._save_to_disk()
            
            return query_type
        except Exception as e:
            print(f"Analysis failed: {e}")
            raise

    def _extract_personal_info(self, query: str) -> Dict:
        """Extract personal information from query with improved pattern matching"""
        info = {}
        query = query.lower()
        
        # Name extraction patterns
        name_patterns = [
            r"my name is (\w+)",
            r"i am (\w+)",
            r"call me (\w+)"
        ]
        
        for pattern in name_patterns:
            match = re.search(pattern, query)
            if match:
                name = match.group(1).strip().title()
                info['user_name'] = [{
                    'value': name,
                    'timestamp': datetime.now().isoformat(),
                    'context': query
                }]
                break
        
        # Attribute extraction patterns
        attr_patterns = {
            'height': r"(?:i am|i'm) (\d+'(?:\d+)?\"|\d+(?:\.\d+)? ?(?:feet|foot|ft))",
            'eye_color': r"(?:i have|my eyes are) (blue|green|brown|hazel|grey|gray) eyes",
            'hair_color': r"(?:i have|my hair is) (blonde|brown|black|red|gray|white) hair"
        }
        
        attributes = []
        for attr, pattern in attr_patterns.items():
            match = re.search(pattern, query)
            if match:
                attributes.append({
                    attr: match.group(1).strip(),
                    'timestamp': datetime.now().isoformat(),
                    'context': query
                })
        
        if attributes:
            info['user_attributes'] = [{
                'value': attributes,
                'timestamp': datetime.now().isoformat(),
                'context': query
            }]
        
        # Relationship extraction patterns
        rel_patterns = {
            'spouse': r"(?:my (?:wife|husband|spouse) is|i'm married to) (\w+)",
            'child': r"my (?:son|daughter|child) is (\w+)",
            'parent': r"my (?:mother|father|parent) is (\w+)"
        }
        
        relationships = []
        for rel, pattern in rel_patterns.items():
            match = re.search(pattern, query)
            if match:
                relationships.append({
                    rel: match.group(1).strip().title(),
                    'timestamp': datetime.now().isoformat(),
                    'context': query
                })
        
        if relationships:
            info['relationships'] = [{
                'value': relationships,
                'timestamp': datetime.now().isoformat(),
                'context': query
            }]
        
        return info

    def add_message(self, thread_id: str, role: str, content: str, importance: float = 0.5) -> None:
        """Add a message to a thread
        
        Args:
            thread_id: ID of the conversation thread
            role: Role of the message sender ('user' or 'assistant')
            content: Content of the message
            importance: Importance score of the message (0.0 to 1.0)
        """
        if thread_id not in self.messages:
            self.messages[thread_id] = []
            
        # Clean markdown formatting before storage
        cleaned_content = self._clean_markdown(content)
            
        message = {
            'role': role,
            'content': cleaned_content,
            'timestamp': datetime.now().isoformat(),
            'importance': importance,
            'is_code': self._is_code_message(cleaned_content)
        }
        
        self.messages[thread_id].append(message)
        
        # Trim to max messages
        if len(self.messages[thread_id]) > MAX_MEMORIES:
            # Sort by importance and recency before trimming
            self.messages[thread_id].sort(
                key=lambda x: (x.get('importance', 0.5), x['timestamp']), 
                reverse=True
            )
            self.messages[thread_id] = self.messages[thread_id][:MAX_MEMORIES]

        # Save after modifications
        self._save_to_disk()

    def _clean_markdown(self, content: str) -> str:
        """Clean up markdown formatting"""
        # Remove HTML tags
        content = re.sub(r'<[^>]+>', '', content)
        
        # Clean up code blocks
        content = re.sub(r'```\w*\n', '```\n', content)
        
        # Remove duplicate newlines
        content = re.sub(r'\n\s*\n', '\n\n', content)
        
        return content.strip()

    def _is_code_message(self, content: str) -> bool:
        """Check if message contains code blocks"""
        return '```' in content or any(
            keyword in content.lower() for keyword in [
                'def ', 'class ', 'function', 'return',
                'import ', 'from ', '#include'
            ]
        )

    def get_context(self, thread_id: str, current_query: str) -> List[Dict]:
        """Get conversation context for a thread"""
        # Start with simple instruction
        context = [{
            'role': 'system',
            'content': (
                "You are a helpful AI assistant. Be direct and natural in conversation.\n"
                "Use the conversation history to answer questions accurately.\n"
                "If you don't have certain information, simply say so.\n"
            )
        }]

        # Add personal context if available
        if self.personal_info['info']:
            context.append({
                'role': 'system',
                'content': (
                    "Personal Information:\n" +
                    self._format_personal_context()
                )
            })
        
        # Add conversation history
        if thread_id in self.messages:
            messages = self.messages[thread_id]
            context.extend([{'role': msg['role'], 'content': msg['content']} for msg in messages])
        
        return context

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

    def clear_thread(self, thread_id: str) -> None:
        """Clear a conversation thread and update storage"""
        if thread_id in self.messages:
            del self.messages[thread_id]
            self._save_to_disk()

    def clear_all(self) -> bool:
        """Clear all threads and disk storage"""
        try:
            # Clear in-memory data first
            self.messages = {}
            self.personal_info = {'info': {}}
            
            # Clean up model resources
            if self.model_manager:
                self.model_manager.cleanup()
            
            # Clear disk storage
            try:
                if self.storage_path.exists():
                    # Force remove all files
                    for file_path in self.storage_path.glob("*"):
                        try:
                            if file_path.is_file():
                                os.chmod(file_path, 0o666)  # Make file writable
                                file_path.unlink()
                                print(f"Deleted file: {file_path}")
                        except Exception as e:
                            print(f"Error deleting file {file_path}: {e}")
                            return False
                    
                    # Only recreate storage files if we have data to save
                    if self.messages or self.personal_info['info']:
                        self._save_to_disk()
                    
                    return True
            except Exception as e:
                print(f"Error clearing storage directory: {e}")
                return False
                
        except Exception as e:
            print(f"Error in clear_all: {e}")
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
            self._cleanup_temp_files()
        except:
            pass

