#!/usr/bin/env python3
"""
Direct Retrieval API for Memory RAG
This is a simplified version of the main.py with just the /retrieve endpoint
"""

import os
import sys
import json
import logging
import pickle
import pathlib
import numpy as np
import faiss
from typing import List, Dict, Any, Optional

import uvicorn
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Constants
INDEX_FILE = "/app/faiss.index"  # FAISS index for vector search
META_FILE = "/app/meta.pkl"      # Page ID metadata for the index
QUOTES_FILE = "/app/quotes.json" # Quote content keyed by page ID

# Global variables
faiss_index = None
page_ids = []
quotes = {}

# FastAPI app
app = FastAPI(
    title="Memory RAG API",
    description="Memory RAG service for Gibsey Bookclub MVP",
    version="0.1.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialization
@app.on_event("startup")
async def startup_event():
    """Initialize resources on startup"""
    global faiss_index, page_ids, quotes
    
    try:
        # Load FAISS index if it exists
        if os.path.exists(INDEX_FILE):
            faiss_index = faiss.read_index(INDEX_FILE)
            logger.info(f"Loaded FAISS index with {faiss_index.ntotal} vectors")
        else:
            logger.error(f"Index file not found: {INDEX_FILE}")
            
        # Load metadata
        if os.path.exists(META_FILE):
            with open(META_FILE, 'rb') as f:
                page_ids = pickle.load(f)
            logger.info(f"Loaded metadata with {len(page_ids)} page IDs")
        else:
            logger.error(f"Metadata file not found: {META_FILE}")
            
        # Load quotes
        if os.path.exists(QUOTES_FILE):
            with open(QUOTES_FILE, 'r') as f:
                quotes = json.load(f)
            logger.info(f"Loaded {len(quotes)} quotes")
        else:
            logger.error(f"Quotes file not found: {QUOTES_FILE}")
            
    except Exception as e:
        logger.error(f"Error during startup: {e}")

def generate_random_embedding(text: str) -> np.ndarray:
    """
    Generate a random embedding vector for testing
    In production, this would call an embedding service
    
    Args:
        text: The text to embed
        
    Returns:
        A normalized embedding vector
    """
    # Random vector with the right dimension
    embedding = np.random.randn(768).astype(np.float32).reshape(1, -1)
    
    # Normalize to unit length (for cosine similarity)
    faiss.normalize_L2(embedding)
    return embedding

# API endpoints
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}

@app.get("/retrieve")
async def retrieve(q: str = Query(..., description="Query text to find relevant quotes"), 
                   k: int = Query(3, description="Number of quotes to return")):
    """Retrieve relevant quotes based on query"""
    global faiss_index, page_ids, quotes
    
    if faiss_index is None:
        raise HTTPException(status_code=503, detail="Vector index not initialized")
        
    if len(page_ids) == 0:
        raise HTTPException(status_code=503, detail="No page IDs loaded")
        
    if len(quotes) == 0:
        raise HTTPException(status_code=503, detail="No quotes loaded")
    
    try:
        # For our test, we'll just use a random embedding
        # In production, this would call an embedding service
        query_vector = generate_random_embedding(q)
        
        # Search the index
        distances, indices = faiss_index.search(query_vector, k)
        
        # Format results
        results = []
        for i, idx in enumerate(indices[0]):
            if idx >= 0 and idx < len(page_ids):
                page_id = page_ids[idx]
                if page_id in quotes:
                    quote = quotes[page_id]
                    results.append({
                        "page_id": page_id,
                        "quote": quote["quote"],
                        "score": float(distances[0][i])
                    })
                    
        # Sort by score (highest first for inner product similarity)
        results.sort(key=lambda x: x["score"], reverse=True)
        
        return results
    
    except Exception as e:
        logger.error(f"Error during retrieval: {e}")
        raise HTTPException(status_code=500, detail=f"Error during retrieval: {str(e)}")

@app.post("/refresh")
async def refresh(data: Dict[str, Any]):
    """
    Refresh endpoint for the embedding consumer to notify of new/updated vectors
    
    Args:
        data: JSON with page_id and vector
    """
    page_id = data.get("page_id")
    vector = data.get("vector")
    
    if not page_id or not vector:
        raise HTTPException(status_code=400, detail="Missing page_id or vector in request")
        
    # In a real implementation, this would update the in-memory index
    # and potentially store the vector for persistence
    
    logger.info(f"Received refresh notification for page_id: {page_id}")
    return {"status": "success", "message": f"Refreshed vector for page_id: {page_id}"}

if __name__ == "__main__":
    # Run the server
    uvicorn.run("direct_retrieval:app", host="0.0.0.0", port=8001, reload=False) 