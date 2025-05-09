#!/usr/bin/env python3
# simple_bootstrap.py - Bootstrap Memory RAG using local data files

import os
import sys
import json
import logging
import pathlib
import numpy as np
import faiss
from typing import List, Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Constants
VECTOR_DIM = 768
INDEX_FILE = "/app/faiss.index"
META_FILE = "/app/meta.pkl"
QUOTES_FILE = "/app/data/quotes.json"

def main():
    """Main bootstrap function"""
    # Create a new FAISS index
    logger.info(f"Creating new FAISS index with dimension {VECTOR_DIM}")
    index = faiss.IndexFlatIP(VECTOR_DIM)  # Inner product index (for cosine similarity)
    
    # Load quotes from data file
    quotes_path = pathlib.Path(QUOTES_FILE)
    if not quotes_path.exists():
        logger.error(f"Quotes file not found: {quotes_path}")
        sys.exit(1)
        
    with quotes_path.open('r') as f:
        quotes = json.load(f)
        
    # Add vectors to the index
    ids = []
    vectors = []
    
    for i, quote in enumerate(quotes):
        page_id = quote.get('page_id')
        embedding = quote.get('embedding')
        
        if page_id and embedding:
            # Convert embedding to numpy array
            vector = np.array(embedding, dtype=np.float32).reshape(1, -1)
            
            # Normalize vector (just to be safe)
            faiss.normalize_L2(vector)
            
            # Add to lists
            ids.append(page_id)
            vectors.append(vector)
            
    # Combine all vectors into a single array
    if vectors:
        all_vectors = np.vstack(vectors)
        
        # Add to index
        index.add(all_vectors)
        logger.info(f"Added {len(ids)} vectors to index")
        
        # Save metadata
        import pickle
        with open(META_FILE, 'wb') as f:
            pickle.dump(ids, f)
            
        # Save index
        faiss.write_index(index, INDEX_FILE)
        logger.info(f"Saved index to {INDEX_FILE} and metadata to {META_FILE}")
        
        # Create memory data structure for quotes
        memory_quotes = {}
        for quote in quotes:
            page_id = quote.get('page_id')
            quote_text = quote.get('quote')
            if page_id and quote_text:
                memory_quotes[page_id] = {
                    'page_id': page_id,
                    'quote': quote_text
                }
                
        # Save quotes in a format the service can use
        with open('/app/quotes.json', 'w') as f:
            json.dump(memory_quotes, f)
            
        logger.info(f"Bootstrapping complete - {len(ids)} vectors indexed")
        
    else:
        logger.error("No valid vectors found")
        sys.exit(1)

if __name__ == "__main__":
    main() 