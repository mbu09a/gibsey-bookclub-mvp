"""
Cross-encoder reranker for Memory RAG service

This module provides a reranker that improves search results by using a cross-encoder model
to rescore retrieval candidates based on their relevance to the query.
"""
import os
import time
import logging
import threading
from typing import List, Dict, Any, Tuple, Optional, Union
from functools import lru_cache

import torch
from sentence_transformers import CrossEncoder

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Environment variables
MODEL_NAME = os.getenv("RERANKER_MODEL", "sentence-transformers/ms-marco-MiniLM-L-6-v2")
USE_RERANKER = os.getenv("RERANKER", "on").lower() in ("on", "true", "1", "yes")
MAX_LENGTH = int(os.getenv("RERANKER_MAX_LENGTH", "384"))  # Maximum sequence length
DEVICE = os.getenv("RERANKER_DEVICE", "cuda" if torch.cuda.is_available() else "cpu")
BATCH_SIZE = int(os.getenv("RERANKER_BATCH_SIZE", "8"))  # Larger batch sizes are faster but use more memory

# Metrics
rerank_latency_seconds = 0.0
rerank_call_count = 0
rerank_lock = threading.Lock()

class RerankerNotInitializedError(Exception):
    """Exception raised when the reranker is not initialized but is used."""
    pass

class Reranker:
    """Cross-encoder reranker for improving search results."""
    
    def __init__(self, model_name: str = MODEL_NAME, device: str = DEVICE):
        """
        Initialize the reranker with the specified model
        
        Args:
            model_name: Name of the cross-encoder model
            device: Device to run the model on ('cuda' or 'cpu')
        """
        self.initialized = False
        self.model_name = model_name
        self.device = device
        self.model = None
        
        # Only initialize if reranker is enabled
        if USE_RERANKER:
            self._initialize()
    
    def _initialize(self):
        """Initialize the cross-encoder model."""
        try:
            logger.info(f"Loading cross-encoder model {self.model_name} on {self.device}...")
            start_time = time.time()
            
            # Load the model with specified parameters
            self.model = CrossEncoder(
                self.model_name,
                device=self.device,
                max_length=MAX_LENGTH
            )
            
            load_time = time.time() - start_time
            logger.info(f"Cross-encoder model loaded in {load_time:.2f} seconds")
            self.initialized = True
        except Exception as e:
            logger.error(f"Failed to initialize cross-encoder: {str(e)}")
            self.initialized = False
    
    def rerank(
        self, 
        query: str, 
        candidates: List[Dict[str, Any]], 
        top_k: int = 6,
        text_key: str = "quote",
        score_key: str = "score"
    ) -> List[Dict[str, Any]]:
        """
        Rerank candidates using the cross-encoder model
        
        Args:
            query: The user's query
            candidates: List of candidate documents
            top_k: Number of top candidates to return
            text_key: Key in candidate dicts to get the text from
            score_key: Key in candidate dicts to store the new score
            
        Returns:
            List of reranked candidates with updated scores
            
        Raises:
            RerankerNotInitializedError: If the reranker is not initialized
        """
        global rerank_latency_seconds, rerank_call_count
        
        # If reranker is disabled, return original candidates sorted by their current score
        if not USE_RERANKER:
            logger.info("Reranker is disabled, returning original candidates")
            # Sort by original score and limit to top_k
            return sorted(candidates, key=lambda x: x.get(score_key, 0), reverse=True)[:top_k]
        
        # Check if reranker is initialized
        if not self.initialized or self.model is None:
            logger.warning("Reranker not initialized, returning original candidates")
            return sorted(candidates, key=lambda x: x.get(score_key, 0), reverse=True)[:top_k]
        
        # Nothing to rerank
        if not candidates:
            return []
        
        start_time = time.time()
        try:
            # Prepare query-passage pairs for cross-encoder
            pairs = [(query, cand[text_key]) for cand in candidates]
            
            # Get cross-encoder scores
            cross_scores = self.model.predict(pairs, batch_size=BATCH_SIZE)
            
            # Update candidates with new scores
            for i, score in enumerate(cross_scores):
                candidates[i][score_key] = float(score)
            
            # Sort by cross-encoder score and get top-k
            reranked = sorted(candidates, key=lambda x: x.get(score_key, 0), reverse=True)[:top_k]
            
            # Log time metrics
            elapsed = time.time() - start_time
            with rerank_lock:
                rerank_latency_seconds = ((rerank_latency_seconds * rerank_call_count) + elapsed) / (rerank_call_count + 1)
                rerank_call_count += 1
            
            logger.info(f"Reranked {len(candidates)} candidates to {len(reranked)} in {elapsed:.3f}s")
            return reranked
            
        except Exception as e:
            logger.error(f"Error during reranking: {str(e)}")
            # Fall back to original ranking on error
            elapsed = time.time() - start_time
            with rerank_lock:
                rerank_latency_seconds = ((rerank_latency_seconds * rerank_call_count) + elapsed) / (rerank_call_count + 1)
                rerank_call_count += 1
            
            # Return original candidates sorted by their existing score
            return sorted(candidates, key=lambda x: x.get(score_key, 0), reverse=True)[:top_k]
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get metrics for the reranker."""
        return {
            "rerank_latency_seconds": rerank_latency_seconds,
            "rerank_call_count": rerank_call_count,
            "reranker_enabled": USE_RERANKER,
            "reranker_initialized": self.initialized,
            "model_name": self.model_name,
            "device": self.device
        }

# Create a global instance of the reranker
reranker = Reranker()

# For testing/direct usage
if __name__ == "__main__":
    # Simple test
    test_query = "What is Gibsey?"
    test_candidates = [
        {"quote": "Malt Gibsey was the town's most respected librarian, known for his remarkable memory.", "score": 0.7},
        {"quote": "The entrance way led to a grand library with soaring ceilings.", "score": 0.8},
        {"quote": "The book was about a character named Gibson who worked at a library.", "score": 0.6},
        {"quote": "In the attic, there was a collection of old books about the town's history.", "score": 0.5},
    ]
    
    # Initialize if needed
    if not reranker.initialized and USE_RERANKER:
        reranker._initialize()
    
    # Test reranking
    reranked = reranker.rerank(test_query, test_candidates)
    print("Reranked results:")
    for r in reranked:
        print(f"{r['score']:.4f}: {r['quote']}")