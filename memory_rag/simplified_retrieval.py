#!/usr/bin/env python3
"""
Ultra-simplified retrieval API that doesn't depend on any external services
"""

import os
import json
import logging
import random
from typing import List, Dict, Any

import uvicorn
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Constants
QUOTES_FILE = "/app/data/quotes.json"

# Load the quotes
try:
    if os.path.exists(QUOTES_FILE):
        with open(QUOTES_FILE, 'r') as f:
            QUOTES = json.load(f)
        logger.info(f"Loaded {len(QUOTES)} quotes from {QUOTES_FILE}")
    else:
        logger.warning(f"Quotes file not found: {QUOTES_FILE}")
        # Fallback quotes if file not found
        QUOTES = [
            {
                "page_id": "1",
                "quote": "The entrance way to the cavern was spiral-shaped, like a nautilus shell, drawing visitors inward through increasingly smaller chambers."
            },
            {
                "page_id": "2",
                "quote": "Shamrock Stillman insisted on placing quartz crystals at regular intervals along the spiral path, saying they would 'cleanse the aura' of anyone who entered."
            },
            {
                "page_id": "3",
                "quote": "The builders had to dynamite the final chamber three times before it reached the desired dimensions, nearly causing a collapse of the entire structure."
            }
        ]
except Exception as e:
    logger.error(f"Error loading quotes: {e}")
    QUOTES = []

# FastAPI app
app = FastAPI(
    title="Simplified Memory RAG API",
    description="Ultra-simplified Memory RAG service for demo purposes",
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

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "quotes_loaded": len(QUOTES)}

@app.get("/retrieve")
async def retrieve(q: str = Query(..., description="Query text"), 
                   k: int = Query(3, description="Number of quotes to return")):
    """
    Simplified retrieve endpoint that returns random quotes
    In production, this would use vector similarity search
    """
    
    # Simple keyword matching as fallback
    matched_quotes = []
    query_terms = q.lower().split()
    
    # First try keyword matching
    for quote_data in QUOTES:
        quote_text = quote_data["quote"].lower()
        
        # Count how many query terms appear in the quote
        matches = sum(1 for term in query_terms if term in quote_text)
        
        if matches > 0:
            matched_quotes.append({
                "page_id": quote_data["page_id"],
                "quote": quote_data["quote"],
                "score": matches / len(query_terms)  # Simple relevance score
            })
    
    # If we found matches, return them sorted by score
    if matched_quotes:
        matched_quotes.sort(key=lambda x: x["score"], reverse=True)
        return matched_quotes[:k]
    
    # If no keyword matches, just return random quotes
    random_quotes = random.sample(QUOTES, min(k, len(QUOTES)))
    return [
        {
            "page_id": quote["page_id"],
            "quote": quote["quote"],
            "score": 0.5  # Arbitrary score for random results
        }
        for quote in random_quotes
    ]

@app.post("/refresh")
async def refresh(data: Dict[str, Any]):
    """
    Simplified refresh endpoint - just acknowledges the request
    """
    page_id = data.get("page_id", "unknown")
    logger.info(f"Received refresh notification for page_id: {page_id}")
    return {"status": "success", "message": f"Acknowledged refresh for page_id: {page_id}"}

if __name__ == "__main__":
    # Run the server
    uvicorn.run("simplified_retrieval:app", host="0.0.0.0", port=8001, reload=False) 