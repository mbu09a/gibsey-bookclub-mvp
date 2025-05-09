import httpx
import os
import logging
import hashlib
from typing import List, Dict, Any, Optional
import numpy as np

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Environment variables
EMBED_URL = os.getenv("EMBED_URL", "http://localhost:11434/api/embeddings")
EMBED_MODEL = os.getenv("EMBED_MODEL", "nomic-embed-text")

# Simple in-memory cache for embeddings
# In production, consider using Redis or another distributed cache
CACHE = {}
MAX_CACHE_SIZE = 1000  # Maximum number of embeddings to cache

async def embed_text(text: str) -> List[float]:
    """
    Generate embedding vector for text using Ollama.
    
    Args:
        text: Text to embed
        
    Returns:
        List of floats representing the embedding vector
    """
    # Generate cache key based on text content
    key = hashlib.md5(text.encode()).hexdigest()
    
    # Check cache first
    if key in CACHE:
        logger.debug(f"Cache hit for key {key[:6]}...")
        return CACHE[key]
    
    # If not in cache, call the embedding API
    try:
        async with httpx.AsyncClient() as client:
            logger.info(f"Generating embedding for text: {text[:50]}...")
            response = await client.post(
                EMBED_URL,
                json={"model": EMBED_MODEL, "prompt": text},
                timeout=30.0  # Long timeout for first inference
            )
            response.raise_for_status()
            data = response.json()
            
            # Extract embedding
            embedding = data.get("embedding")
            if not embedding:
                logger.error(f"No embedding found in response: {data}")
                return np.zeros(768).tolist()  # Return zeros as fallback
            
            # Cache the result
            if len(CACHE) >= MAX_CACHE_SIZE:
                # Remove a random key if cache is full
                CACHE.pop(next(iter(CACHE)))
            CACHE[key] = embedding
            
            logger.info(f"Generated embedding of dimension {len(embedding)}")
            return embedding
            
    except Exception as e:
        logger.error(f"Error generating embedding: {e}")
        # Return zeros as fallback
        return np.zeros(768).tolist()

# Utility function to clear the cache
def clear_cache():
    """Clear the embedding cache."""
    global CACHE
    CACHE = {}
    logger.info("Embedding cache cleared")