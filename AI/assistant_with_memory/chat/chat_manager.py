from typing import AsyncIterator, Iterator, List, Dict
from models.llm import ChatLLM
from memory.memory_manager import MemoryManager
import json
import logging
import traceback
import asyncio

class ChatManager:
    def __init__(self, user_id: str):
        self.llm = ChatLLM()
        self.memory = MemoryManager(user_id, self.llm)
        logging.basicConfig(level=logging.DEBUG)
        self.logger = logging.getLogger(__name__)
        
    def _create_memory_prompt(self, message: str, response: str) -> str:
        """Creates a prompt for the LLM to analyze conversation for memory storage"""
        system_prompt = """<|im_start|>system
Extract and store conversation information in JSON format.
Memory types:
- semantic: facts, traits, preferences
- episodic: events, interactions
- procedural: behaviors, patterns

Return format:
{
    "memory_items": [
        {
            "type": "semantic|episodic|procedural",
            "entity": "entity_name",
            "information": "fact_to_remember",
            "confidence": "High|Low",
            "source": "Direct|Inferred"
        }
    ]
}
<|im_end|>"""

        user_prompt = f"""<|im_start|>user
User: {message}
Assistant: {response}
<|im_end|>"""

        return f"""{system_prompt}
{user_prompt}
<|im_start|>assistant"""

    def _get_context_prompt(self, memories: List[Dict]) -> str:
        """Creates a prompt incorporating relevant memories as context"""
        context = []
        
        for memory in memories:
            memory_type = memory['memory_type']
            info = memory['content'].get('information', '')
            context.append(f"- **{memory_type}**: {info}")

        prompt = f"""<|im_start|>system
You are a helpful AI assistant with access to conversation memory.
Format your responses using markdown for better readability:

- Use **bold** for emphasis and important points
- Use *italics* for names and terms
- Use `code blocks` for technical terms
- Use bullet points and numbered lists for organization
- Use ### for section headers
- Use > for quotes or highlighting key information
- Use --- for separating sections
- Use color formatting like this: <span style='color: blue'>text</span>
- Use tables for structured information
- Use proper spacing and line breaks for readability

Previous context:
{chr(10).join(context)}
<|im_end|>
<|im_start|>user
Respond naturally using the context provided. Use rich markdown formatting for an engaging response.
<|im_end|>
<|im_start|>assistant"""

        return prompt

    async def chat(self, message: str) -> AsyncIterator[str]:
        """Main chat function that processes messages and manages memory"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("Starting chat interaction")
            self.logger.debug(f"Raw message: {message}")
            
            # Get relevant memories
            memories = self.memory.get_relevant_memories(message)
            self.logger.debug(f"Retrieved {len(memories)} relevant memories")
            
            # Create conversation context
            context_prompt = self._get_context_prompt(memories)
            
            # Format the user message
            user_message = f"""<|im_start|>user
{message}<|im_end|>
<|im_start|>assistant"""
            
            # Stream the response
            response = ""
            buffer = ""  # Add buffer for cleaning output
            
            async for token in self.llm.stream_chat([
                {"role": "system", "content": context_prompt},
                {"role": "user", "content": user_message}
            ]):
                response += token
                buffer += token
                
                # Clean the output before yielding
                if '_based_on_context_provided:' in buffer:
                    buffer = buffer.replace('_based_on_context_provided:', '')
                if '_based_on_given_memories' in buffer:
                    buffer = buffer.replace('_based_on_given_memories', '')
                    
                # Only yield when we have a complete word or punctuation
                if buffer.endswith((' ', '.', '!', '?', '\n')):
                    yield buffer
                    buffer = ""
            
            # Yield any remaining buffer
            if buffer:
                yield buffer
                
            # Process memory after response
            memory_prompt = f"""<|im_start|>system
Extract facts about the user from this conversation. Return in JSON format:
{{
    "memory_items": [
        {{
            "type": "semantic",
            "entity": "user",
            "information": "specific fact about user",
            "confidence": "High",
            "source": "Direct"
        }}
    ]
}}
<|im_end|>
<|im_start|>user
Previous memories:
{chr(10).join(m['content'].get('information', '') for m in memories)}

Current conversation:
User: {message}
Assistant: {response}
<|im_end|>
<|im_start|>assistant"""

            # Process memory
            memory_response = ""
            async for token in self.llm.stream_chat([{"role": "user", "content": memory_prompt}]):
                memory_response += token
                
            try:
                memory_data = json.loads(memory_response)
                self.logger.debug(f"Parsed memory data: {json.dumps(memory_data, indent=2)}")
                self.memory.add_memory(memory_data)
            except json.JSONDecodeError as e:
                self.logger.error(f"JSON parse error: {str(e)}")
                self.logger.error(f"Failed response: {memory_response}")

        except Exception as e:
            self.logger.error(f"Error in chat: {str(e)}")
            self.logger.error(f"Traceback: {traceback.format_exc()}")
            raise
