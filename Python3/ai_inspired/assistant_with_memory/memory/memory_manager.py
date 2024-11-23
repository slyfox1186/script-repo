from typing import Dict, List, Optional
from datetime import datetime, timezone
from .sqlite_store import SQLiteStore
from .memory_types import MemoryAnalysis, MemoryItem, MemoryEntry, parse_memory_response, format_memory_for_storage
from uuid import uuid4
import json
import asyncio
import traceback
import logging
from pathlib import Path
import re

class MemoryManager:
    def __init__(self, user_id: str, llm=None):
        self.user_id = user_id
        self.store = SQLiteStore()
        self.llm = llm
        
        # Configure logging
        self.logger = logging.getLogger(__name__)
        
        # Reset log file on initialization
        self._reset_log_file()
        
        # Load existing memories
        self._load_memories()
        
    def _reset_log_file(self):
        """Reset log file to prevent overwhelming logs"""
        try:
            # Get log file path
            log_dir = Path(__file__).parent.parent / "logs"
            log_dir.mkdir(exist_ok=True)
            log_file = log_dir / f"memory_manager_{datetime.now().strftime('%Y%m%d')}.log"
            
            # Clear existing handlers
            if self.logger.handlers:
                for handler in self.logger.handlers:
                    self.logger.removeHandler(handler)
                    
            # Create fresh file handler with empty log
            with open(log_file, 'w') as f:
                f.write(f"# Log file reset on {datetime.now().isoformat()}\n")
                
            # Setup new handler
            file_handler = logging.FileHandler(log_file)
            console_handler = logging.StreamHandler()
            
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            )
            
            file_handler.setFormatter(formatter)
            console_handler.setFormatter(formatter)
            
            self.logger.addHandler(file_handler)
            self.logger.addHandler(console_handler)
            self.logger.setLevel(logging.DEBUG)
            
            self.logger.debug(f"Log file reset: {log_file}")
            
        except Exception as e:
            print(f"Error resetting log file: {str(e)}")

    def _load_memories(self):
        """Load existing memories from the database"""
        self.logger.debug("="*50)
        self.logger.debug("[MEM_LOAD] Starting memory load operation")
        try:
            self.logger.debug("[MEM_LOAD] Requesting memories from SQLite store")
            memories = self.store.load_all_memories(self.user_id)
            self.logger.debug(f"[MEM_LOAD] Retrieved {len(memories)} memories from store")
            
            # Analyze memory types
            memory_types = {}
            entity_counts = {}
            importance_levels = {"low": 0, "medium": 0, "high": 0}
            
            for memory in memories:
                # Track memory types
                mem_type = memory.get("memory_type", "unknown")
                memory_types[mem_type] = memory_types.get(mem_type, 0) + 1
                
                # Track entities
                entity = memory.get("entity_id")
                if entity:
                    entity_counts[entity] = entity_counts.get(entity, 0) + 1
                    
                # Track importance
                importance = memory.get("importance_score", 0)
                if importance >= 0.8:
                    importance_levels["high"] += 1
                elif importance >= 0.4:
                    importance_levels["medium"] += 1
                else:
                    importance_levels["low"] += 1
                    
                self.logger.debug(f"[MEM_LOAD] Memory {memory['id']}:")
                self.logger.debug(f"[MEM_LOAD] - Type: {mem_type}")
                self.logger.debug(f"[MEM_LOAD] - Entity: {entity}")
                self.logger.debug(f"[MEM_LOAD] - Content: {json.dumps(memory.get('content', {}), indent=2)}")
                self.logger.debug(f"[MEM_LOAD] - Importance: {importance}")
                self.logger.debug(f"[MEM_LOAD] - Created: {memory.get('created_at')}")
                
            self.logger.debug("[MEM_LOAD] Memory distribution analysis:")
            self.logger.debug(f"[MEM_LOAD] Memory types: {json.dumps(memory_types, indent=2)}")
            self.logger.debug(f"[MEM_LOAD] Entity counts: {json.dumps(entity_counts, indent=2)}")
            self.logger.debug(f"[MEM_LOAD] Importance levels: {json.dumps(importance_levels, indent=2)}")
            
        except Exception as e:
            self.logger.error("[MEM_LOAD] Error loading memories")
            self.logger.error(f"[MEM_LOAD] Error: {str(e)}")
            self.logger.error(f"[MEM_LOAD] Traceback: {traceback.format_exc()}")
        finally:
            self.logger.debug("[MEM_LOAD] Memory load operation complete")
            self.logger.debug("="*50)

    def add_memory(self, memory_data: Dict):
        """Add a new memory with proper format transformation"""
        try:
            self.logger.debug("Adding new memory")
            self.logger.debug(f"Raw memory data: {memory_data}")
            
            # Parse memory data using pydantic models
            memory_analysis = parse_memory_response(json.dumps(memory_data))
            self.logger.debug(f"Parsed memory analysis: {memory_analysis.dict()}")
            
            # Store each memory item
            for item in memory_analysis.memory_items:
                memory_id = str(uuid4())
                memory_entry = format_memory_for_storage(item, memory_id)
                self.logger.debug(f"Formatted memory entry: {memory_entry.dict()}")
                
                # Store in database
                self.store.add_memory(self.user_id, memory_entry.dict())
                
            self.logger.debug(f"Added {len(memory_analysis.memory_items)} memories")
                
        except Exception as e:
            self.logger.error(f"Error adding memory: {str(e)}")
            self.logger.error(f"Memory data: {memory_data}")
            self.logger.error(f"Traceback: {traceback.format_exc()}")

    def get_relevant_memories(self, context: str, k: int = 5) -> List[Dict]:
        """Get relevant memories using Tree of Thoughts"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[MEMORY_RETRIEVAL] Starting memory retrieval")
            self.logger.debug(f"[MEMORY_RETRIEVAL] Context: {context}")
            self.logger.debug(f"[MEMORY_RETRIEVAL] Max results: {k}")
            
            # Extract potential entity mentions from context
            entity_ids = self._extract_entity_mentions([{"content": context}])
            self.logger.debug(f"[MEMORY_RETRIEVAL] Extracted entity IDs: {entity_ids}")
            
            # Search memories
            self.logger.debug("[MEMORY_RETRIEVAL] Searching memories in database")
            memories = self.store.search_memories(
                self.user_id,
                entity_ids=entity_ids,
                max_results=k
            )
            self.logger.debug(f"[MEMORY_RETRIEVAL] Found {len(memories)} memories")
            
            # Update access patterns
            self.logger.debug("[MEMORY_RETRIEVAL] Updating access patterns")
            for memory in memories:
                self.logger.debug(f"[MEMORY_RETRIEVAL] Updating memory: {memory['id']}")
                memory["last_accessed"] = datetime.now(timezone.utc).isoformat()
                memory["access_count"] = memory.get("access_count", 0) + 1
                self.store.update_memory(self.user_id, memory["id"], memory)
                
            self.logger.debug("[MEMORY_RETRIEVAL] Memory retrieval complete")
            self.logger.debug(f"[MEMORY_RETRIEVAL] Retrieved memories: {json.dumps(memories, indent=2)}")
            self.logger.debug("="*50)
            return memories
            
        except Exception as e:
            self.logger.error("[MEMORY_RETRIEVAL] Error getting memories")
            self.logger.error(f"[MEMORY_RETRIEVAL] Error: {str(e)}")
            self.logger.error(f"[MEMORY_RETRIEVAL] Traceback: {traceback.format_exc()}")
            return []

    def _extract_entity_mentions(self, conversation_history: List[Dict]) -> List[str]:
        """Extract potential entity IDs/names from conversation"""
        entities = set()
        
        try:
            for message in conversation_history:
                content = message.get("content", "")
                
                if self.llm:
                    # Direct, focused prompt
                    prompt = f"""<|im_start|>system
Extract entities from text. Return only comma-separated list.
Required entities:
- Names (Jeff, Rosemary)
- Ages (33, 38)
- Pets (Tahiri, Chloe)
- Skills (coding, yoga)
- Interests (space, computers)
- Objects (furniture, computers)
<|im_end|>
<|im_start|>user
Text: {content}
<|im_end|>
<|im_start|>assistant"""

                    response = self.llm.invoke([{"role": "system", "content": prompt}])
                    
                    if response and isinstance(response, str):
                        # Process entities
                        extracted = [e.strip().lower() for e in response.split(",")]
                        for entity in extracted:
                            if self._is_valid_entity(entity):
                                entities.add(entity)
                                # Add associated numbers
                                numbers = re.findall(r'\d+', entity)
                                entities.update(numbers)
            
            # Add core entities
            entities.update([self.user_id, "user", "assistant"])
            return list(entities)
            
        except Exception as e:
            self.logger.error(f"Error extracting entities: {str(e)}")
            return [self.user_id]

    def _is_valid_entity(self, entity: str) -> bool:
        """Validate entity"""
        if len(entity) < 2:
            return False
        if any(c in entity for c in [':', '"', "'", '<', '>', '{']):
            return False
        if entity.isdigit() and len(entity) < 3:
            return False
        if entity.lower() in {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for'}:
            return False
        if any(word in entity.lower() for word in {'error', 'invalid', 'none', 'null', 'undefined'}):
            return False
        return True

    def _calculate_importance(self, memory_data: Dict) -> float:
        """Calculate memory importance score"""
        base_score = 0.5
        
        # Adjust based on confidence
        if memory_data.get("confidence") == "High":
            base_score += 0.3
            
        # Adjust based on source
        if memory_data.get("source") == "direct":
            base_score += 0.2
            
        return min(base_score, 1.0)