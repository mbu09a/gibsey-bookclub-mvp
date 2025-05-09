"""
FAISS indexer for Memory RAG service
Handles vector storage and retrieval using an in-memory FAISS index
"""
import faiss
import numpy as np
import threading
import logging
from typing import List, Dict, Optional, Tuple, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Vector dimension - matches the embedding model (nomic-embed-text)
DIM = 768

class VectorIndex:
    def __init__(self):
        """Initialize the FAISS vector index"""
        # Initialize the FAISS index - using IndexFlatIP for cosine similarity
        # This is an exact, non-quantized index suitable for smaller datasets
        self.index = faiss.IndexFlatIP(DIM)
        
        # Mapping from FAISS index position to page_id
        self.id_map: Dict[int, str] = {}
        
        # Reverse mapping from page_id to FAISS index position
        self.reverse_map: Dict[str, int] = {}
        
        # Next available index position
        self.next_id = 0
        
        # Thread lock for concurrent access
        self.lock = threading.Lock()
        
        logger.info(f"Initialized FAISS IndexFlatIP with dimension {DIM}")

    def add_vector(self, page_id: str, vector: List[float]) -> None:
        """
        Add a vector to the index, or update if page_id already exists
        
        Args:
            page_id: Unique identifier for the page
            vector: Vector embedding as list of floats (DIM-dimension)
        """
        # Convert to numpy array and reshape
        vec_np = np.array(vector, dtype=np.float32).reshape(1, DIM)
        
        # Normalize for cosine similarity
        faiss.normalize_L2(vec_np)
        
        with self.lock:
            # Check if this page_id already exists in the index
            if page_id in self.reverse_map:
                old_idx = self.reverse_map[page_id]
                logger.debug(f"Updating vector for page_id {page_id} at index position {old_idx}")
                
                # Remove the old mapping
                del self.id_map[old_idx]
                del self.reverse_map[page_id]
                
                # We can't directly update vectors in an IndexFlatIP, so we'll:
                # 1. Create a new index
                # 2. Copy all vectors except the one we're updating
                # 3. Add the updated vector
                # 4. Replace the old index
                
                # This approach works well for smaller indexes (<100k vectors)
                # For larger datasets, consider using IndexIDMap or storing in an external database
                
                old_index = self.index
                old_size = old_index.ntotal
                
                if old_size > 1:
                    # Create new index
                    new_index = faiss.IndexFlatIP(DIM)
                    
                    # Get all vectors
                    vectors = faiss.rev_swig_ptr(old_index.get_xb(), old_size * DIM).reshape(old_size, DIM)
                    
                    # Create new id map
                    new_id_map = {}
                    new_reverse_map = {}
                    new_id = 0
                    
                    # Add all vectors except the one we're updating
                    for i in range(old_size):
                        if i != old_idx:
                            # Find the page_id for this index
                            old_page_id = None
                            for pid, idx in self.reverse_map.items():
                                if idx == i:
                                    old_page_id = pid
                                    break
                            
                            if old_page_id:
                                # Add to new index
                                vector_to_add = vectors[i].reshape(1, DIM)
                                new_index.add(vector_to_add)
                                
                                # Update maps
                                new_id_map[new_id] = old_page_id
                                new_reverse_map[old_page_id] = new_id
                                new_id += 1
                    
                    # Update index and maps
                    self.index = new_index
                    self.id_map = new_id_map
                    self.reverse_map = new_reverse_map
                    self.next_id = new_id
                else:
                    # If only one vector in index, just reset
                    self.index = faiss.IndexFlatIP(DIM)
                    self.id_map = {}
                    self.reverse_map = {}
                    self.next_id = 0
            
            # Now add the new/updated vector
            self.index.add(vec_np)
            self.id_map[self.next_id] = page_id
            self.reverse_map[page_id] = self.next_id
            logger.debug(f"Added vector for page_id {page_id} at index position {self.next_id}")
            self.next_id += 1
            
            logger.info(f"Vector index now contains {self.index.ntotal} vectors")

    def search(self, query_vector: List[float], k: int = 4) -> List[Tuple[str, float]]:
        """
        Search the index for most similar vectors to the query
        
        Args:
            query_vector: Query vector embedding
            k: Number of results to return
            
        Returns:
            List of tuples (page_id, similarity_score)
        """
        # Convert to numpy array and reshape
        query_np = np.array(query_vector, dtype=np.float32).reshape(1, DIM)
        
        # Normalize for cosine similarity
        faiss.normalize_L2(query_np)
        
        with self.lock:
            if self.index.ntotal == 0:
                logger.warning("Search attempted on empty index")
                return []
            
            # Limit k to the number of vectors in the index
            k_effective = min(k, self.index.ntotal)
            
            # D contains distances (similarity scores), I contains indices
            D, I = self.index.search(query_np, k_effective)
            
            # Collect results as (page_id, score) tuples
            results = []
            for i in range(I.shape[1]):
                if I[0, i] != -1:  # Skip invalid indices
                    idx = int(I[0, i])
                    score = float(D[0, i])
                    if idx in self.id_map:
                        page_id = self.id_map[idx]
                        results.append((page_id, score))
            
            logger.info(f"Search returned {len(results)} results")
            return results

    def remove_vector(self, page_id: str) -> bool:
        """
        Remove a vector from the index
        
        Args:
            page_id: Unique identifier for the page
            
        Returns:
            True if removed, False if not found
        """
        with self.lock:
            if page_id not in self.reverse_map:
                logger.warning(f"Attempted to remove non-existent page_id: {page_id}")
                return False
            
            # Get the index of the vector to remove
            idx_to_remove = self.reverse_map[page_id]
            
            # Similar to update, we need to recreate the index without this vector
            old_index = self.index
            old_size = old_index.ntotal
            
            # Create new index
            new_index = faiss.IndexFlatIP(DIM)
            
            if old_size > 1:
                # Get all vectors
                vectors = faiss.rev_swig_ptr(old_index.get_xb(), old_size * DIM).reshape(old_size, DIM)
                
                # Create new id map
                new_id_map = {}
                new_reverse_map = {}
                new_id = 0
                
                # Add all vectors except the one we're removing
                for i in range(old_size):
                    if i != idx_to_remove:
                        # Find the page_id for this index
                        old_page_id = None
                        for pid, idx in self.reverse_map.items():
                            if idx == i:
                                old_page_id = pid
                                break
                        
                        if old_page_id:
                            # Add to new index
                            vector_to_add = vectors[i].reshape(1, DIM)
                            new_index.add(vector_to_add)
                            
                            # Update maps
                            new_id_map[new_id] = old_page_id
                            new_reverse_map[old_page_id] = new_id
                            new_id += 1
                
                # Update index and maps
                self.index = new_index
                self.id_map = new_id_map
                self.reverse_map = new_reverse_map
                self.next_id = new_id
            else:
                # If only one vector in index, just reset
                self.index = faiss.IndexFlatIP(DIM)
                self.id_map = {}
                self.reverse_map = {}
                self.next_id = 0
            
            logger.info(f"Removed vector for page_id {page_id}, index now contains {self.index.ntotal} vectors")
            return True

    def clear(self) -> None:
        """Clear the index of all vectors"""
        with self.lock:
            self.index = faiss.IndexFlatIP(DIM)
            self.id_map = {}
            self.reverse_map = {}
            self.next_id = 0
            logger.info("Vector index cleared")

    def bulk_add(self, page_vectors: Dict[str, List[float]]) -> None:
        """
        Add multiple vectors to the index in a batch operation
        
        Args:
            page_vectors: Dictionary mapping page_ids to vector embeddings
        """
        if not page_vectors:
            logger.warning("Attempted bulk add with empty dictionary")
            return
        
        # Convert to numpy array
        page_ids = list(page_vectors.keys())
        vectors = np.array([page_vectors[pid] for pid in page_ids], dtype=np.float32)
        
        # Normalize for cosine similarity
        faiss.normalize_L2(vectors)
        
        with self.lock:
            # For bulk loading, we'll create a new index
            new_index = faiss.IndexFlatIP(DIM)
            new_index.add(vectors)
            
            # Create new maps
            new_id_map = {i: page_ids[i] for i in range(len(page_ids))}
            new_reverse_map = {page_ids[i]: i for i in range(len(page_ids))}
            
            # Update index and maps
            self.index = new_index
            self.id_map = new_id_map
            self.reverse_map = new_reverse_map
            self.next_id = len(page_ids)
            
            logger.info(f"Bulk added {len(page_ids)} vectors to index")

    def get_stats(self) -> Dict[str, Any]:
        """Get statistics about the index"""
        with self.lock:
            return {
                "total_vectors": self.index.ntotal,
                "dimension": DIM,
                "index_type": "IndexFlatIP",
                "memory_usage_bytes": self.index.ntotal * DIM * 4,  # Approximate memory usage (4 bytes per float)
                "unique_page_ids": len(self.id_map)
            }

# Singleton instance of the vector index
vector_index = VectorIndex()