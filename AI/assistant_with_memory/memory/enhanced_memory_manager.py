import json
from typing import List, Dict, Optional
import logging
from uuid import uuid4
from datetime import datetime, timezone
from .memory_types import *
from .sqlite_store import SQLiteStore
import traceback

class EnhancedMemoryManager:
    def __init__(self, user_id: str, llm=None):
        self.user_id = user_id
        self.llm = llm
        self.store = SQLiteStore()
        self.logger = logging.getLogger(__name__)
        
        # Configure logging
        if not self.logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            )
            handler.setFormatter(formatter)
            self.logger.addHandler(handler)
            self.logger.setLevel(logging.DEBUG)
            
    def _create_memory_prompt(self, conversation_history: List[Dict]) -> str:
        """Creates a prompt for the LLM to analyze memory implications"""
        system_prompt = """<|im_start|>system
You are an advanced memory analysis system that helps maintain a chatbot's memory.
Your task is to analyze conversations and extract important information to remember.

You must respond in valid JSON format with this structure:
{
    "new_memories": [
        {
            "memory_type": "semantic|episodic|procedural",
            "entity_id": "name_or_identifier",
            "content": {
                "information": "the information to remember",
                "confidence": "High|Low",
                "source": "Direct|Inferred"
            }
        }
    ]
}

Focus on extracting:
1. Personal information (name, age, relationships)
2. Preferences and interests
3. Important facts and experiences
4. Skills and abilities
5. Future plans and aspirations
<|im_end|>"""

        # Format conversation history
        conversation_text = "\n".join([
            f"{'User' if msg.get('role') == 'user' else 'Assistant'}: {msg.get('content', '')}"
            for msg in conversation_history
        ])

        user_prompt = f"""<|im_start|>user
Analyze this conversation and determine what should be remembered:

Conversation:
{conversation_text}

Extract all important information about the user and their characteristics.
<|im_end|>"""

        return f"""{system_prompt}
{user_prompt}
<|im_start|>assistant"""

    def _get_relevant_context(self, conversation_history: List[Dict]) -> Dict:
        """Gets existing memories and entities relevant to the conversation"""
        try:
            # Extract potential entity mentions from conversation
            entity_mentions = self._extract_entity_mentions(conversation_history)
            
            # Get existing entities
            existing_entities = []
            for entity_id in entity_mentions:
                entity = self.store.get_entity(self.user_id, entity_id)
                if entity:
                    existing_entities.append(entity)
                    
            # Get relevant memories using Tree of Thoughts
            memories = self.store.search_memories(
                self.user_id,
                entity_ids=entity_mentions,
                max_results=10
            )
            
            return {
                "entities": existing_entities,
                "memories": memories
            }
            
        except Exception as e:
            self.logger.error(f"Error getting context: {str(e)}")
            self.logger.error(f"Traceback: {traceback.format_exc()}")
            return {"entities": [], "memories": []}
            
    def _extract_entity_mentions(self, conversation_history: List[Dict]) -> List[str]:
        """Extract potential entity IDs/names from conversation"""
        entities = set()
        
        try:
            # Simple extraction based on message content
            for message in conversation_history:
                content = message.get("content", "")
                # Extract names, places, etc using the LLM
                if self.llm:
                    entity_prompt = f"""Extract entity names (people, places, things) from this text. 
                    Return as a comma-separated list:
                    {content}"""
                    response = self.llm.invoke([{"role": "user", "content": entity_prompt}])
                    entities.update([e.strip() for e in response.split(",")])
                    
        except Exception as e:
            self.logger.error(f"Error extracting entities: {str(e)}")
            
        return list(entities)

    def process_conversation(self, conversation_history: List[Dict]) -> None:
        """Process conversation using Tree of Thoughts to update memories"""
        self.logger.debug("Processing conversation for memory updates")
        
        try:
            # Generate memory analysis prompt
            prompt = self._create_memory_prompt(conversation_history)
            
            # Get LLM's analysis using proper prompt format
            messages = [
                {"role": "system", "content": prompt}
            ]
            
            response = ""
            for token in self.llm.stream_chat(messages):
                response += token
                
            # Parse response
            analysis = json.loads(response)
            
            # Store new memories and entity updates
            self._store_memory_updates(analysis)
            
            self.logger.debug(f"Memory processing complete: {analysis.get('reasoning')}")
            
        except Exception as e:
            self.logger.error(f"Error processing memories: {str(e)}")
            self.logger.error(f"Traceback: {traceback.format_exc()}")
            
    def _store_memory_updates(self, analysis: Dict) -> None:
        """Stores new memories and entity updates from analysis"""
        try:
            # Add validation and cleanup of JSON response
            if isinstance(analysis, str):
                analysis = json.loads(analysis)
            
            # Ensure the response has the expected structure
            if not isinstance(analysis, dict) or "new_memories" not in analysis:
                self.logger.error("Invalid memory analysis format")
                return
            
            # Store new memories with better error handling
            for memory in analysis.get("new_memories", []):
                try:
                    # Add metadata
                    memory["id"] = str(uuid4())
                    memory["created_at"] = datetime.now(timezone.utc).isoformat()
                    memory["last_accessed"] = datetime.now(timezone.utc).isoformat()
                    
                    self.store.add_memory(self.user_id, memory)
                except Exception as e:
                    self.logger.error(f"Error storing individual memory: {str(e)}")
                    continue
                
        except Exception as e:
            self.logger.error(f"Error storing updates: {str(e)}")
            self.logger.error(f"Raw analysis: {analysis}")
            self.logger.error(f"Traceback: {traceback.format_exc()}")

    def get_relevant_memories(self, query: str, max_results: int = 10) -> List[Dict]:
        """Get relevant memories using Tree of Thoughts"""
        try:
            # Extract entities from query
            entity_mentions = self._extract_entity_mentions([{"content": query}])
            
            # Search memories
            memories = self.store.search_memories(
                self.user_id,
                entity_ids=entity_mentions,
                max_results=max_results
            )
            
            # Update access patterns
            for memory in memories:
                memory["last_accessed"] = datetime.now(timezone.utc).isoformat()
                memory["access_count"] = memory.get("access_count", 0) + 1
                self.store.update_memory(self.user_id, memory["id"], memory)
                
            return memories
            
        except Exception as e:
            self.logger.error(f"Error getting memories: {str(e)}")
            self.logger.error(f"Traceback: {traceback.format_exc()}")
            return [] 
