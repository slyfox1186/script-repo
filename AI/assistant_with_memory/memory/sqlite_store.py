# memory/sqlite_store.py

import sqlite3
from typing import Dict, List, Optional
from datetime import datetime, timezone, timedelta
import json
import numpy as np
import traceback
import logging
from pathlib import Path
import os
import time

class SQLiteStore:
    def __init__(self, db_str = None):
        """Initialize SQLite store with schema for memories and entities"""
        if db_str is None:
            db_path = Path(__file__).parent.parent / "memory_store" / "memory.db"
            db_path.parent.mkdir(exist_ok=True)
            
        self.db_path = str(db_path)
        self.logger = logging.getLogger(__name__)
        if not self.logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            )
            handler.setFormatter(formatter)
            self.logger.addHandler(handler)
            self.logger.setLevel(logging.DEBUG)
            
        self._init_db()
        
    def _init_db(self):
        """Initialize database with proper schema for memory storage"""
        with sqlite3.connect(self.db_path) as conn:
            # Enable foreign keys
            conn.execute("PRAGMA foreign_keys = ON")
            
            # Create memories table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS memories (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    memory_type TEXT NOT NULL,
                    entity_id TEXT,
                    content TEXT NOT NULL,
                    confidence REAL,
                    importance_score REAL DEFAULT 0.0,
                    source TEXT,
                    created_at TEXT NOT NULL,
                    last_accessed TEXT NOT NULL,
                    access_count INTEGER DEFAULT 0,
                    embedding BLOB,
                    marked_for_deletion INTEGER DEFAULT 0,
                    processed INTEGER DEFAULT 0
                )
            """)
            
            # Create memory associations table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS memory_associations (
                    memory_id TEXT,
                    associated_memory_id TEXT,
                    FOREIGN KEY(memory_id) REFERENCES memories(id),
                    FOREIGN KEY(associated_memory_id) REFERENCES memories(id),
                    PRIMARY KEY(memory_id, associated_memory_id)
                )
            """)
            
            # Create entities table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS entities (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    type TEXT NOT NULL,
                    attributes TEXT,
                    first_seen TEXT NOT NULL,
                    last_seen TEXT NOT NULL
                )
            """)
            
            # Create entity relationships table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS entity_relationships (
                    entity_id TEXT,
                    related_entity_id TEXT,
                    relationship_type TEXT NOT NULL,
                    FOREIGN KEY(entity_id) REFERENCES entities(id),
                    FOREIGN KEY(related_entity_id) REFERENCES entities(id),
                    PRIMARY KEY(entity_id, related_entity_id, relationship_type)
                )
            """)
            
            # Create indices for performance
            conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_user ON memories(user_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(memory_type)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_entity ON memories(entity_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_importance ON memories(importance_score)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_entities_user ON entities(user_id)")
            
            # Enable WAL mode for better concurrent access
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA synchronous=NORMAL")
            conn.execute("PRAGMA cache_size=-2000")  # 2MB cache
            
            conn.commit()
            
            self.logger.debug("Database initialized with correct schema")
            
    def load_all_memories(self, user_id: str) -> List[Dict]:
        """Load all memories for a user"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute("""
                    SELECT m.*, GROUP_CONCAT(ma.associated_memory_id) as associations
                    FROM memories m
                    LEFT JOIN memory_associations ma ON m.id = ma.memory_id
                    WHERE m.user_id = ? AND m.marked_for_deletion = 0
                    GROUP BY m.id
                    ORDER BY m.created_at DESC
                """, (user_id,))
                
                memories = []
                for row in cursor:
                    memory = self._row_to_dict(row)
                    if row["associations"]:
                        memory["associations"] = row["associations"].split(",")
                    memories.append(memory)
                    
                self.logger.debug(f"Loaded {len(memories)} memories for user {user_id}")
                return memories
                
        except Exception as e:
            self.logger.error(f"Error loading memories: {str(e)}")
            self.logger.error(traceback.format_exc())
            return []
            
    def load_all_entities(self, user_id: str) -> List[Dict]:
        """Load all entities for a user"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute("""
                    SELECT e.*, GROUP_CONCAT(er.relationship_type || ':' || er.related_entity_id) as relationships
                    FROM entities e
                    LEFT JOIN entity_relationships er ON e.id = er.entity_id
                    WHERE e.user_id = ?
                    GROUP BY e.id
                """, (user_id,))
                
                entities = []
                for row in cursor:
                    entity = {
                        "id": row["id"],
                        "name": row["name"],
                        "type": row["type"],
                        "attributes": json.loads(row["attributes"]),
                        "first_seen": row["first_seen"],
                        "last_seen": row["last_seen"],
                        "relationships": {}
                    }
                    
                    if row["relationships"]:
                        for rel in row["relationships"].split(","):
                            rel_type, rel_id = rel.split(":")
                            if rel_type not in entity["relationships"]:
                                entity["relationships"][rel_type] = []
                            entity["relationships"][rel_type].append(rel_id)
                            
                    entities.append(entity)
                    
                self.logger.debug(f"Loaded {len(entities)} entities for user {user_id}")
                return entities
                
        except Exception as e:
            self.logger.error(f"Error loading entities: {str(e)}")
            self.logger.error(traceback.format_exc())
            return []

    def add_memory(self, user_id: str, memory_entry: Dict):
        """Add a new memory entry to the database"""
        try:
            self.logger.debug(f"Adding memory to SQLite DB at {self.db_path}")
            self.logger.debug(f"Memory entry: {json.dumps(memory_entry, indent=2)}")
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT INTO memories 
                    (id, user_id, memory_type, entity_id, content, confidence,
                    importance_score, source, created_at, last_accessed, access_count,
                    marked_for_deletion, processed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)
                """, (
                    memory_entry["id"],
                    user_id,
                    memory_entry.get("memory_type", "semantic").lower(),
                    memory_entry.get("entity_id"),
                    json.dumps(memory_entry.get("content", {})),
                    memory_entry.get("confidence", 1.0),
                    memory_entry.get("importance_score", 0.0),
                    memory_entry.get("source", "direct"),
                    memory_entry.get("created_at"),
                    memory_entry.get("last_accessed"),
                    memory_entry.get("access_count", 0)
                ))
                
                # Add associations if any
                if memory_entry.get("associations"):
                    for assoc_id in memory_entry["associations"]:
                        cursor.execute("""
                            INSERT OR IGNORE INTO memory_associations
                            (memory_id, associated_memory_id)
                            VALUES (?, ?)
                        """, (memory_entry["id"], assoc_id))
                        
                self.logger.debug(f"Memory added with ID: {memory_entry['id']}")
                self.logger.debug(f"Row count: {cursor.rowcount}")
                
            # Verify the memory was written
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM memories WHERE id = ?", (memory_entry["id"],))
                result = cursor.fetchone()
                self.logger.debug(f"Verification read: {result}")
                
        except Exception as e:
            self.logger.error(f"Error adding memory: {str(e)}")
            self.logger.error(f"Memory entry: {memory_entry}")
            self.logger.error(f"Traceback: {traceback.format_exc()}")
            raise

    def _row_to_dict(self, row: sqlite3.Row) -> Dict:
        """Convert a database row to a dictionary"""
        memory_dict = {
            "id": row["id"],
            "memory_type": row["memory_type"],
            "entity_id": row["entity_id"],
            "content": json.loads(row["content"]),
            "confidence": row["confidence"],
            "source": row["source"],
            "created_at": row["created_at"],
            "last_accessed": row["last_accessed"],
            "access_count": row["access_count"],
            "importance_score": row["importance_score"]
        }
        
        if row["embedding"]:
            memory_dict["embedding"] = self._decode_embedding(row["embedding"])
            
        return memory_dict
  
    def search_memories(
        self,
        user_id: str,
        entity_ids: Optional[List[str]] = None,
        max_results: int = 10
    ) -> List[Dict]:
        """Search memories by user ID and optional entity IDs"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[DB_SEARCH] Starting memory search")
            
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                # Base query with content search
                query = """
                    SELECT DISTINCT m.*, GROUP_CONCAT(ma.associated_memory_id) as associations
                    FROM memories m
                    LEFT JOIN memory_associations ma ON m.id = ma.memory_id
                    WHERE m.user_id = ? 
                    AND m.marked_for_deletion = 0
                """
                params = [user_id]
                
                # Add entity and content search
                if entity_ids:
                    entity_conditions = []
                    for entity_id in entity_ids:
                        entity_conditions.extend([
                            "m.entity_id LIKE ?",
                            "m.content LIKE ?"
                        ])
                        params.extend([f"%{entity_id}%", f"%{entity_id}%"])
                    
                    if entity_conditions:
                        query += f" AND ({' OR '.join(entity_conditions)})"
                
                # Add ordering and limit
                query += """ 
                    GROUP BY m.id
                    ORDER BY m.importance_score DESC, m.last_accessed DESC
                    LIMIT ?
                """
                params.append(max_results)
                
                self.logger.debug(f"[DB_SEARCH] Query: {query}")
                self.logger.debug(f"[DB_SEARCH] Params: {params}")
                
                cursor = conn.execute(query, params)
                results = [self._row_to_dict(row) for row in cursor]
                
                self.logger.debug(f"[DB_SEARCH] Found {len(results)} results")
                return results
                
        except Exception as e:
            self.logger.error(f"[DB_SEARCH] Error: {str(e)}")
            self.logger.error(traceback.format_exc())
            return []
  
    def verify_database_integrity(self) -> Dict:
        """Verify database integrity and report status"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[DB_VERIFY] Starting database integrity check")
            
            results = {
                "tables": {},
                "indices": {},
                "foreign_keys": [],
                "errors": []
            }
            
            with sqlite3.connect(self.db_path) as conn:
                # Check if database is locked
                self.logger.debug("[DB_VERIFY] Checking database lock status")
                cursor = conn.execute("PRAGMA busy_timeout")
                results["lock_timeout"] = cursor.fetchone()[0]
                
                # Check WAL mode
                self.logger.debug("[DB_VERIFY] Checking WAL mode")
                cursor = conn.execute("PRAGMA journal_mode")
                results["journal_mode"] = cursor.fetchone()[0]
                
                # Check table structure
                self.logger.debug("[DB_VERIFY] Checking table structure")
                for table in ["memories", "memory_associations", "entities", "entity_relationships"]:
                    cursor = conn.execute(f"PRAGMA table_info({table})")
                    columns = cursor.fetchall()
                    results["tables"][table] = {
                        "column_count": len(columns),
                        "columns": [col[1] for col in columns],
                        "row_count": conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                    }
                    self.logger.debug(f"[DB_VERIFY] Table {table}: {json.dumps(results['tables'][table], indent=2)}")
                
                # Check indices
                self.logger.debug("[DB_VERIFY] Checking indices")
                cursor = conn.execute("SELECT * FROM sqlite_master WHERE type='index'")
                for idx in cursor.fetchall():
                    results["indices"][idx[1]] = {
                        "table": idx[2],
                        "sql": idx[4]
                    }
                    self.logger.debug(f"[DB_VERIFY] Index {idx[1]}: {json.dumps(results['indices'][idx[1]], indent=2)}")
                
                # Verify foreign key constraints
                self.logger.debug("[DB_VERIFY] Checking foreign key constraints")
                cursor = conn.execute("PRAGMA foreign_key_check")
                fk_violations = cursor.fetchall()
                if fk_violations:
                    results["errors"].append(f"Foreign key violations found: {fk_violations}")
                    self.logger.error(f"[DB_VERIFY] Foreign key violations: {fk_violations}")
                    
            self.logger.debug("[DB_VERIFY] Database verification complete")
            self.logger.debug(f"[DB_VERIFY] Results: {json.dumps(results, indent=2)}")
            return results
            
        except Exception as e:
            self.logger.error(f"[DB_VERIFY] Error verifying database: {str(e)}")
            self.logger.error(f"[DB_VERIFY] Traceback: {traceback.format_exc()}")
            return {"error": str(e)}

    def analyze_memory_distribution(self, user_id: str) -> Dict:
        """Analyze memory distribution and patterns"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[MEM_ANALYZE] Starting memory distribution analysis")
            self.logger.debug(f"[MEM_ANALYZE] User ID: {user_id}")
            
            stats = {
                "total_memories": 0,
                "by_type": {},
                "by_confidence": {},
                "by_source": {},
                "by_importance": {
                    "high": 0,    # 0.8-1.0
                    "medium": 0,  # 0.4-0.7
                    "low": 0      # 0.0-0.3
                },
                "access_patterns": {
                    "never_accessed": 0,
                    "recently_accessed": 0,  # last 24h
                    "frequently_accessed": 0  # >5 accesses
                }
            }
            
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                # Get total count
                cursor = conn.execute("SELECT COUNT(*) FROM memories WHERE user_id = ?", (user_id,))
                stats["total_memories"] = cursor.fetchone()[0]
                self.logger.debug(f"[MEM_ANALYZE] Total memories: {stats['total_memories']}")
                
                # Analyze by type
                cursor = conn.execute("""
                    SELECT memory_type, COUNT(*) as count 
                    FROM memories 
                    WHERE user_id = ? 
                    GROUP BY memory_type
                """, (user_id,))
                for row in cursor:
                    stats["by_type"][row["memory_type"]] = row["count"]
                self.logger.debug(f"[MEM_ANALYZE] Distribution by type: {stats['by_type']}")
                
                # Analyze by confidence
                cursor = conn.execute("""
                    SELECT confidence, COUNT(*) as count 
                    FROM memories 
                    WHERE user_id = ? 
                    GROUP BY confidence
                """, (user_id,))
                for row in cursor:
                    stats["by_confidence"][str(row["confidence"])] = row["count"]
                self.logger.debug(f"[MEM_ANALYZE] Distribution by confidence: {stats['by_confidence']}")
                
                # Analyze importance scores
                cursor = conn.execute("SELECT importance_score FROM memories WHERE user_id = ?", (user_id,))
                for row in cursor:
                    score = row["importance_score"]
                    if score >= 0.8:
                        stats["by_importance"]["high"] += 1
                    elif score >= 0.4:
                        stats["by_importance"]["medium"] += 1
                    else:
                        stats["by_importance"]["low"] += 1
                self.logger.debug(f"[MEM_ANALYZE] Distribution by importance: {stats['by_importance']}")
                
                # Analyze access patterns
                now = datetime.now(timezone.utc)
                day_ago = now - timedelta(days=1)
                
                cursor = conn.execute("""
                    SELECT 
                        COUNT(*) FILTER (WHERE access_count = 0) as never,
                        COUNT(*) FILTER (WHERE last_accessed > ?) as recent,
                        COUNT(*) FILTER (WHERE access_count > 5) as frequent
                    FROM memories 
                    WHERE user_id = ?
                """, (day_ago.isoformat(), user_id))
                row = cursor.fetchone()
                stats["access_patterns"]["never_accessed"] = row["never"]
                stats["access_patterns"]["recently_accessed"] = row["recent"]
                stats["access_patterns"]["frequently_accessed"] = row["frequent"]
                
                self.logger.debug(f"[MEM_ANALYZE] Access patterns: {stats['access_patterns']}")
                
            return stats
            
        except Exception as e:
            self.logger.error(f"[MEM_ANALYZE] Error analyzing memories: {str(e)}")
            self.logger.error(f"[MEM_ANALYZE] Traceback: {traceback.format_exc()}")
            return {"error": str(e)}

    def verify_memory_persistence(self, memory_id: str) -> Dict:
        """Verify a specific memory was properly persisted"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[MEM_VERIFY] Starting memory persistence verification")
            self.logger.debug(f"[MEM_VERIFY] Memory ID: {memory_id}")
            
            results = {
                "exists": False,
                "data": None,
                "associations": [],
                "integrity": True,
                "issues": []
            }
            
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                # Check main memory entry
                cursor = conn.execute("""
                    SELECT * FROM memories WHERE id = ?
                """, (memory_id,))
                row = cursor.fetchone()
                
                if row:
                    results["exists"] = True
                    memory_dict = self._row_to_dict(row)
                    results["data"] = memory_dict
                    self.logger.debug(f"[MEM_VERIFY] Memory found: {json.dumps(memory_dict, indent=2)}")
                    
                    # Verify content JSON
                    try:
                        content = json.loads(row["content"])
                        if not isinstance(content, dict):
                            results["integrity"] = False
                            results["issues"].append("Content is not a valid JSON object")
                    except json.JSONDecodeError:
                        results["integrity"] = False
                        results["issues"].append("Content is not valid JSON")
                    
                    # Check associations
                    cursor = conn.execute("""
                        SELECT associated_memory_id 
                        FROM memory_associations 
                        WHERE memory_id = ?
                    """, (memory_id,))
                    results["associations"] = [row[0] for row in cursor]
                    self.logger.debug(f"[MEM_VERIFY] Found {len(results['associations'])} associations")
                    
                    # Verify required fields
                    required_fields = ["memory_type", "content", "confidence", "created_at"]
                    for field in required_fields:
                        if not row[field]:
                            results["integrity"] = False
                            results["issues"].append(f"Missing required field: {field}")
                    
                else:
                    self.logger.warning(f"[MEM_VERIFY] Memory {memory_id} not found")
                    
            self.logger.debug(f"[MEM_VERIFY] Verification results: {json.dumps(results, indent=2)}")
            return results
            
        except Exception as e:
            self.logger.error(f"[MEM_VERIFY] Error verifying memory: {str(e)}")
            self.logger.error(f"[MEM_VERIFY] Traceback: {traceback.format_exc()}")
            return {"error": str(e)}

    def check_memory_retrieval(self, user_id: str, query_params: Dict) -> Dict:
        """Test memory retrieval with different query parameters"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[MEM_CHECK] Starting memory retrieval check")
            self.logger.debug(f"[MEM_CHECK] User ID: {user_id}")
            self.logger.debug(f"[MEM_CHECK] Query params: {query_params}")
            
            results = {
                "queries": {},
                "timing": {},
                "issues": []
            }
            
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                # Test entity-based retrieval
                start_time = time.time()
                if query_params.get("entity_ids"):
                    cursor = conn.execute("""
                        SELECT COUNT(*) FROM memories 
                        WHERE user_id = ? AND entity_id IN ({})
                    """.format(','.join(['?']*len(query_params["entity_ids"]))),
                        [user_id] + query_params["entity_ids"])
                    results["queries"]["entity_matches"] = cursor.fetchone()[0]
                results["timing"]["entity_query"] = time.time() - start_time
                
                # Test importance-based retrieval
                start_time = time.time()
                cursor = conn.execute("""
                    SELECT COUNT(*) FROM memories 
                    WHERE user_id = ? AND importance_score >= ?
                """, (user_id, query_params.get("min_importance", 0.5)))
                results["queries"]["importance_matches"] = cursor.fetchone()[0]
                results["timing"]["importance_query"] = time.time() - start_time
                
                # Test type-based retrieval
                if query_params.get("memory_types"):
                    start_time = time.time()
                    cursor = conn.execute("""
                        SELECT COUNT(*) FROM memories 
                        WHERE user_id = ? AND memory_type IN ({})
                    """.format(','.join(['?']*len(query_params["memory_types"]))),
                        [user_id] + query_params["memory_types"])
                    results["queries"]["type_matches"] = cursor.fetchone()[0]
                    results["timing"]["type_query"] = time.time() - start_time
                
                # Check index usage
                self.logger.debug("[MEM_CHECK] Analyzing query plans")
                for query_type in ["entity", "importance", "type"]:
                    cursor = conn.execute("EXPLAIN QUERY PLAN " + 
                        "SELECT * FROM memories WHERE user_id = ? AND importance_score > 0.5", 
                        (user_id,))
                    plan = cursor.fetchall()
                    if not any("USING INDEX" in str(row) for row in plan):
                        results["issues"].append(f"Index not used for {query_type} query")
                    self.logger.debug(f"[MEM_CHECK] Query plan for {query_type}: {plan}")
                
            self.logger.debug(f"[MEM_CHECK] Check results: {json.dumps(results, indent=2)}")
            return results
            
        except Exception as e:
            self.logger.error(f"[MEM_CHECK] Error checking retrieval: {str(e)}")
            self.logger.error(f"[MEM_CHECK] Traceback: {traceback.format_exc()}")
            return {"error": str(e)}

    def diagnose_memory_issues(self, user_id: str) -> Dict:
        """Run comprehensive diagnostics on memory system"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[MEM_DIAG] Starting memory system diagnostics")
            self.logger.debug(f"[MEM_DIAG] User ID: {user_id}")
            
            diagnostics = {
                "database": {},
                "memories": {},
                "retrieval": {},
                "issues": [],
                "recommendations": []
            }
            
            # Check database health
            db_status = self.verify_database_integrity()
            diagnostics["database"] = db_status
            if "errors" in db_status and db_status["errors"]:
                diagnostics["issues"].extend(db_status["errors"])
                
            # Analyze memory patterns
            memory_stats = self.analyze_memory_distribution(user_id)
            diagnostics["memories"] = memory_stats
            
            if memory_stats.get("total_memories", 0) == 0:
                diagnostics["issues"].append("No memories found for user")
                diagnostics["recommendations"].append("Verify memory creation process")
                
            # Test retrieval with different parameters
            retrieval_test = self.check_memory_retrieval(user_id, {
                "entity_ids": ["user_preferences", "user_conversation"],
                "memory_types": ["semantic", "episodic"],
                "min_importance": 0.5
            })
            diagnostics["retrieval"] = retrieval_test
            
            if retrieval_test.get("issues"):
                diagnostics["issues"].extend(retrieval_test["issues"])
                
            # Check for common issues
            with sqlite3.connect(self.db_path) as conn:
                # Check for orphaned associations
                cursor = conn.execute("""
                    SELECT COUNT(*) FROM memory_associations ma 
                    LEFT JOIN memories m ON ma.memory_id = m.id 
                    WHERE m.id IS NULL
                """)
                orphaned = cursor.fetchone()[0]
                if orphaned > 0:
                    diagnostics["issues"].append(f"Found {orphaned} orphaned associations")
                    
                # Check for duplicate memories
                cursor = conn.execute("""
                    SELECT content, COUNT(*) as cnt 
                    FROM memories 
                    WHERE user_id = ?
                    GROUP BY content 
                    HAVING cnt > 1
                """, (user_id,))
                duplicates = cursor.fetchall()
                if duplicates:
                    diagnostics["issues"].append(f"Found {len(duplicates)} duplicate memories")
                    
            self.logger.debug(f"[MEM_DIAG] Diagnostic results: {json.dumps(diagnostics, indent=2)}")
            return diagnostics
            
        except Exception as e:
            self.logger.error(f"[MEM_DIAG] Error running diagnostics: {str(e)}")
            self.logger.error(f"[MEM_DIAG] Traceback: {traceback.format_exc()}")
            return {"error": str(e)}

    def update_memory(self, user_id: str, memory_id: str, memory_data: Dict):
        """Update an existing memory entry"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[MEM_UPDATE] Starting memory update")
            self.logger.debug(f"[MEM_UPDATE] User ID: {user_id}")
            self.logger.debug(f"[MEM_UPDATE] Memory ID: {memory_id}")
            self.logger.debug(f"[MEM_UPDATE] Update data: {json.dumps(memory_data, indent=2)}")
            
            # First verify memory exists and belongs to user
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute(
                    "SELECT * FROM memories WHERE id = ? AND user_id = ?", 
                    (memory_id, user_id)
                )
                existing = cursor.fetchone()
                
                if not existing:
                    self.logger.error("[MEM_UPDATE] Memory not found or doesn't belong to user")
                    self.logger.error(f"[MEM_UPDATE] Memory ID: {memory_id}")
                    self.logger.error(f"[MEM_UPDATE] User ID: {user_id}")
                    raise ValueError("Memory not found or unauthorized")
                    
                self.logger.debug("[MEM_UPDATE] Found existing memory:")
                self.logger.debug(f"[MEM_UPDATE] Existing data: {existing}")
                
                # Prepare update data
                update_fields = []
                update_values = []
                
                if "content" in memory_data:
                    self.logger.debug("[MEM_UPDATE] Updating content field")
                    self.logger.debug(f"[MEM_UPDATE] New content: {json.dumps(memory_data['content'], indent=2)}")
                    update_fields.append("content = ?")
                    update_values.append(json.dumps(memory_data["content"]))
                    
                if "last_accessed" in memory_data:
                    self.logger.debug("[MEM_UPDATE] Updating last_accessed field")
                    self.logger.debug(f"[MEM_UPDATE] New last_accessed: {memory_data['last_accessed']}")
                    update_fields.append("last_accessed = ?")
                    update_values.append(memory_data["last_accessed"])
                    
                if "access_count" in memory_data:
                    self.logger.debug("[MEM_UPDATE] Updating access_count field")
                    self.logger.debug(f"[MEM_UPDATE] New access_count: {memory_data['access_count']}")
                    update_fields.append("access_count = ?")
                    update_values.append(memory_data["access_count"])
                    
                if "importance_score" in memory_data:
                    self.logger.debug("[MEM_UPDATE] Updating importance_score field")
                    self.logger.debug(f"[MEM_UPDATE] New importance_score: {memory_data['importance_score']}")
                    update_fields.append("importance_score = ?")
                    update_values.append(memory_data["importance_score"])
                    
                # Execute update
                if update_fields:
                    query = f"""
                        UPDATE memories 
                        SET {', '.join(update_fields)}
                        WHERE id = ? AND user_id = ?
                    """
                    update_values.extend([memory_id, user_id])
                    
                    self.logger.debug("[MEM_UPDATE] Executing update query:")
                    self.logger.debug(f"[MEM_UPDATE] Query: {query}")
                    self.logger.debug(f"[MEM_UPDATE] Values: {update_values}")
                    
                    cursor.execute(query, update_values)
                    self.logger.debug(f"[MEM_UPDATE] Rows affected: {cursor.rowcount}")
                    
                    # Verify update
                    cursor.execute("SELECT * FROM memories WHERE id = ?", (memory_id,))
                    updated = cursor.fetchone()
                    self.logger.debug("[MEM_UPDATE] Verification after update:")
                    self.logger.debug(f"[MEM_UPDATE] Updated data: {updated}")
                    
            self.logger.debug("[MEM_UPDATE] Memory update complete")
            self.logger.debug("="*50)
            
        except Exception as e:
            self.logger.error(f"[MEM_UPDATE] Error updating memory: {str(e)}")
            self.logger.error(f"[MEM_UPDATE] Memory ID: {memory_id}")
            self.logger.error(f"[MEM_UPDATE] Update data: {memory_data}")
            self.logger.error(f"[MEM_UPDATE] Traceback: {traceback.format_exc()}")
            raise

    def get_entity(self, user_id: str, entity_id: str) -> Optional[Dict]:
        """Get a specific entity by ID"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[ENTITY_GET] Starting entity retrieval")
            self.logger.debug(f"[ENTITY_GET] User ID: {user_id}")
            self.logger.debug(f"[ENTITY_GET] Entity ID: {entity_id}")
            
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                # Get entity data
                self.logger.debug("[ENTITY_GET] Executing entity query")
                cursor = conn.execute("""
                    SELECT e.*, GROUP_CONCAT(er.relationship_type || ':' || er.related_entity_id) as relationships
                    FROM entities e
                    LEFT JOIN entity_relationships er ON e.id = er.entity_id
                    WHERE e.id = ? AND e.user_id = ?
                    GROUP BY e.id
                """, (entity_id, user_id))
                
                row = cursor.fetchone()
                
                if row:
                    self.logger.debug("[ENTITY_GET] Entity found")
                    self.logger.debug(f"[ENTITY_GET] Raw data: {dict(row)}")
                    
                    # Build entity dictionary
                    entity = {
                        "id": row["id"],
                        "name": row["name"],
                        "type": row["type"],
                        "attributes": json.loads(row["attributes"]),
                        "first_seen": row["first_seen"],
                        "last_seen": row["last_seen"],
                        "relationships": {}
                    }
                    
                    # Process relationships
                    if row["relationships"]:
                        self.logger.debug("[ENTITY_GET] Processing relationships")
                        for rel in row["relationships"].split(","):
                            rel_type, rel_id = rel.split(":")
                            if rel_type not in entity["relationships"]:
                                entity["relationships"][rel_type] = []
                            entity["relationships"][rel_type].append(rel_id)
                            self.logger.debug(f"[ENTITY_GET] Added relationship: {rel_type} -> {rel_id}")
                    
                    self.logger.debug("[ENTITY_GET] Final entity data:")
                    self.logger.debug(f"[ENTITY_GET] {json.dumps(entity, indent=2)}")
                    return entity
                else:
                    self.logger.debug("[ENTITY_GET] Entity not found")
                    return None
                
        except Exception as e:
            self.logger.error(f"[ENTITY_GET] Error retrieving entity: {str(e)}")
            self.logger.error(f"[ENTITY_GET] Entity ID: {entity_id}")
            self.logger.error(f"[ENTITY_GET] Traceback: {traceback.format_exc()}")
            return None

    def update_entity(self, user_id: str, entity_data: Dict):
        """Update an existing entity"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[ENTITY_UPDATE] Starting entity update")
            self.logger.debug(f"[ENTITY_UPDATE] User ID: {user_id}")
            self.logger.debug(f"[ENTITY_UPDATE] Entity data: {json.dumps(entity_data, indent=2)}")
            
            with sqlite3.connect(self.db_path) as conn:
                # Verify entity exists
                cursor = conn.execute(
                    "SELECT * FROM entities WHERE id = ? AND user_id = ?",
                    (entity_data["id"], user_id)
                )
                existing = cursor.fetchone()
                
                if not existing:
                    self.logger.error("[ENTITY_UPDATE] Entity not found or unauthorized")
                    raise ValueError("Entity not found or unauthorized")
                    
                self.logger.debug("[ENTITY_UPDATE] Found existing entity:")
                self.logger.debug(f"[ENTITY_UPDATE] Existing data: {existing}")
                
                # Update entity
                self.logger.debug("[ENTITY_UPDATE] Updating entity data")
                cursor.execute("""
                    UPDATE entities 
                    SET name = ?, type = ?, attributes = ?, last_seen = ?
                    WHERE id = ? AND user_id = ?
                """, (
                    entity_data["name"],
                    entity_data["type"],
                    json.dumps(entity_data["attributes"]),
                    entity_data["last_seen"],
                    entity_data["id"],
                    user_id
                ))
                
                self.logger.debug(f"[ENTITY_UPDATE] Entity rows updated: {cursor.rowcount}")
                
                # Update relationships
                if "relationships" in entity_data:
                    self.logger.debug("[ENTITY_UPDATE] Updating relationships")
                    
                    # Remove old relationships
                    cursor.execute(
                        "DELETE FROM entity_relationships WHERE entity_id = ?",
                        (entity_data["id"],)
                    )
                    self.logger.debug("[ENTITY_UPDATE] Cleared old relationships")
                    
                    # Add new relationships
                    for rel_type, related_ids in entity_data["relationships"].items():
                        self.logger.debug(f"[ENTITY_UPDATE] Adding relationships of type: {rel_type}")
                        for related_id in related_ids:
                            cursor.execute("""
                                INSERT INTO entity_relationships
                                (entity_id, related_entity_id, relationship_type)
                                VALUES (?, ?, ?)
                            """, (entity_data["id"], related_id, rel_type))
                            self.logger.debug(f"[ENTITY_UPDATE] Added relationship: {rel_type} -> {related_id}")
                            
                # Verify update
                cursor.execute(
                    "SELECT * FROM entities WHERE id = ?",
                    (entity_data["id"],)
                )
                updated = cursor.fetchone()
                self.logger.debug("[ENTITY_UPDATE] Verification after update:")
                self.logger.debug(f"[ENTITY_UPDATE] Updated data: {updated}")
                
            self.logger.debug("[ENTITY_UPDATE] Entity update complete")
            self.logger.debug("="*50)
            
        except Exception as e:
            self.logger.error(f"[ENTITY_UPDATE] Error updating entity: {str(e)}")
            self.logger.error(f"[ENTITY_UPDATE] Entity data: {entity_data}")
            self.logger.error(f"[ENTITY_UPDATE] Traceback: {traceback.format_exc()}")
            raise

    def _decode_embedding(self, blob: bytes) -> List[float]:
        """Decode embedding blob from database"""
        try:
            self.logger.debug("="*50)
            self.logger.debug("[EMBED_DECODE] Starting embedding decode")
            self.logger.debug(f"[EMBED_DECODE] Blob size: {len(blob)} bytes")
            
            # Convert blob to numpy array
            self.logger.debug("[EMBED_DECODE] Converting blob to numpy array")
            arr = np.frombuffer(blob, dtype=np.float32)
            self.logger.debug(f"[EMBED_DECODE] Array shape: {arr.shape}")
            self.logger.debug(f"[EMBED_DECODE] Array dtype: {arr.dtype}")
            
            # Convert to list
            result = arr.tolist()
            self.logger.debug(f"[EMBED_DECODE] Decoded {len(result)} dimensions")
            self.logger.debug(f"[EMBED_DECODE] First 5 values: {result[:5]}")
            self.logger.debug(f"[EMBED_DECODE] Last 5 values: {result[-5:]}")
            
            self.logger.debug("[EMBED_DECODE] Embedding decode complete")
            self.logger.debug("="*50)
            return result
            
        except Exception as e:
            self.logger.error(f"[EMBED_DECODE] Error decoding embedding: {str(e)}")
            self.logger.error(f"[EMBED_DECODE] Blob size: {len(blob)}")
            self.logger.error(f"[EMBED_DECODE] Traceback: {traceback.format_exc()}")
            raise
  
    def verify_memory_storage(self, memory_id: str) -> bool:
        """Verify a memory was properly stored"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute(
                    "SELECT * FROM memories WHERE id = ?",
                    (memory_id,)
                )
                result = cursor.fetchone()
                return result is not None
        except Exception as e:
            self.logger.error(f"Error verifying memory storage: {str(e)}")
            return False
  
