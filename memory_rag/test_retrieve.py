#!/usr/bin/env python3
"""
Test script to directly test Memory RAG retrieval
"""

import os
import sys
import json
import logging
import pathlib
import faiss
import pickle
import numpy as np
from typing import List, Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Constants
INDEX_FILE = "/app/faiss.index"
META_FILE = "/app/meta.pkl"
QUOTES_FILE = "/app/quotes.json"

def main():
    # Load FAISS index if it exists
    if not os.path.exists(INDEX_FILE):
        logger.error(f"Index file not found: {INDEX_FILE}")
        sys.exit(1)
        
    # Load index
    index = faiss.read_index(INDEX_FILE)
    logger.info(f"Loaded FAISS index with {index.ntotal} vectors")
    
    # Load metadata
    if not os.path.exists(META_FILE):
        logger.error(f"Metadata file not found: {META_FILE}")
        sys.exit(1)
        
    with open(META_FILE, 'rb') as f:
        ids = pickle.load(f)
    logger.info(f"Loaded metadata with {len(ids)} page IDs")
    
    # Load quotes
    if not os.path.exists(QUOTES_FILE):
        logger.error(f"Quotes file not found: {QUOTES_FILE}")
        sys.exit(1)
        
    with open(QUOTES_FILE, 'r') as f:
        quotes = json.load(f)
    logger.info(f"Loaded {len(quotes)} quotes")
    
    # Create mock query vector
    query = "Tell me about Shamrock Stillman and the spiral shape"
    
    # Use random vector for testing (in a real service, this would be embedded)
    query_vector = np.random.randn(768).astype(np.float32).reshape(1, -1)
    faiss.normalize_L2(query_vector)
    
    # Search
    k = 3  # Number of results to return
    distances, indices = index.search(query_vector, k)
    
    # Format results
    results = []
    for i, idx in enumerate(indices[0]):
        if idx >= 0 and idx < len(ids):
            page_id = ids[idx]
            if page_id in quotes:
                quote = quotes[page_id]
                results.append({
                    "page_id": page_id,
                    "quote": quote["quote"],
                    "score": float(distances[0][i])
                })
                
    # Print results
    logger.info(f"Query: {query}")
    logger.info(f"Found {len(results)} results:")
    for result in results:
        logger.info(f"Page {result['page_id']} (score: {result['score']:.4f}): {result['quote']}")
    
    # This simulates what should be returned from the /retrieve endpoint
    print(json.dumps(results, indent=2))

if __name__ == "__main__":
    main() 