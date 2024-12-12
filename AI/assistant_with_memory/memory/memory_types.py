from typing import List, Dict, Optional, Union
from pydantic import BaseModel, Field
from datetime import datetime
import json

class MemoryItem(BaseModel):
    """Individual memory item format from LLM analysis"""
    type: str = Field(description="Type of memory (semantic/episodic/procedural)")
    entity: str = Field(description="Entity this memory is about")
    information: str = Field(description="The actual information to store")
    confidence: str = Field(description="Confidence level (High/Low)")
    source: str = Field(description="Source of information (Direct/Inferred)")

class MemoryAnalysis(BaseModel):
    """Format for LLM's memory analysis response"""
    memory_items: List[MemoryItem] = Field(description="List of memory items to store")

class MemoryEntry(BaseModel):
    """Base class for stored memory entries"""
    id: str = Field(description="Unique identifier for this memory")
    memory_type: str = Field(description="Type of memory (semantic/episodic/procedural)")
    entity_id: Optional[str] = Field(description="ID of the entity this memory is about")
    content: Dict = Field(description="The actual memory content")
    confidence: float = Field(description="Confidence score (0-1)")
    importance_score: float = Field(default=0.0, description="Importance score (0-1)")
    source: str = Field(description="Source of memory (direct/inferred)")
    created_at: str = Field(description="ISO format timestamp of creation")
    last_accessed: str = Field(description="ISO format timestamp of last access")
    access_count: int = Field(default=0, description="Number of times accessed")
    associations: List[str] = Field(default_factory=list, description="IDs of related memories")

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }

class Entity(BaseModel):
    """Represents a person, place, or thing the bot knows about"""
    id: str = Field(description="Unique identifier for this entity")
    name: str = Field(description="Name of the entity")
    type: str = Field(description="Type of entity (person/place/thing/concept)")
    attributes: Dict = Field(default_factory=dict, description="Known attributes")
    first_seen: str = Field(description="When this entity was first encountered")
    last_seen: str = Field(description="When this entity was last encountered")
    relationships: Dict[str, List[str]] = Field(
        default_factory=dict,
        description="Relationships to other entities by type"
    )

class MemorySearchQuery(BaseModel):
    """Format for memory search/retrieval requests"""
    entity_ids: Optional[List[str]] = Field(description="Entities to search for")
    memory_types: Optional[List[str]] = Field(description="Types of memories to retrieve")
    keywords: Optional[List[str]] = Field(description="Keywords to search for")
    time_range: Optional[Dict] = Field(description="Time range to search within")
    min_confidence: Optional[float] = Field(description="Minimum confidence threshold")
    max_results: Optional[int] = Field(description="Maximum number of results to return")

def parse_memory_response(response_text: str) -> MemoryAnalysis:
    """Parse LLM's memory analysis response"""
    try:
        data = json.loads(response_text)
        return MemoryAnalysis(**data)
    except Exception as e:
        raise ValueError(f"Failed to parse memory response: {str(e)}")

def format_memory_for_storage(memory_item: MemoryItem, memory_id: str) -> MemoryEntry:
    """Format a memory item for storage"""
    now = datetime.utcnow().isoformat()
    
    # Calculate importance score
    importance_score = 0.5  # Base score
    if memory_item.confidence == "High":
        importance_score += 0.3
    if memory_item.source == "Direct":
        importance_score += 0.2
    importance_score = min(importance_score, 1.0)
    
    return MemoryEntry(
        id=memory_id,
        memory_type=memory_item.type.lower(),
        entity_id=memory_item.entity,
        content={
            "information": memory_item.information,
            "confidence": memory_item.confidence,
            "source": memory_item.source
        },
        confidence=1.0 if memory_item.confidence == "High" else 0.5,
        source=memory_item.source.lower(),
        created_at=now,
        last_accessed=now,
        access_count=0,
        importance_score=importance_score
    ) 
