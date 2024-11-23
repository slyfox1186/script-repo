from abc import ABC, abstractmethod
from typing import Dict, List
import json
import os
from datetime import datetime, timezone
from config import MEMORY_DIR

class BaseMemory(ABC):
    def __init__(self, user_id: str):
        self.user_id = user_id
        self.memory_file = os.path.join(MEMORY_DIR, f"{user_id}.json")
        self.created_at = datetime.now(timezone.utc).isoformat()
        self._load_memories()

    def _load_memories(self):
        if os.path.exists(self.memory_file):
            with open(self.memory_file, 'r') as f:
                data = json.load(f)
                self.memories = data.get("memories", {
                    "semantic": {},
                    "episodic": [],
                    "procedural": []
                })
                self.created_at = data.get("created_at", self.created_at)
        else:
            self.memories = {
                "semantic": {},
                "episodic": [],
                "procedural": []
            }

    def save_memories(self):
        with open(self.memory_file, 'w') as f:
            json.dump({
                "memories": self.memories,
                "created_at": self.created_at,
                "last_updated": datetime.now(timezone.utc).isoformat()
            }, f, indent=2)

    @abstractmethod
    def add_memory(self, content: Dict):
        pass

    @abstractmethod
    def get_relevant_memories(self, context: str) -> List[Dict]:
        pass 