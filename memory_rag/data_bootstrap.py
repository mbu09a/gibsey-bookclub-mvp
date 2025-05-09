#!/usr/bin/env python3
# data_bootstrap.py - Generate test data for Memory RAG

import os
import json
import numpy as np
import logging
import pathlib
from typing import List, Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Vector dimension
VECTOR_DIM = 768

# Sample quotes from "The Entrance Way"
SAMPLE_QUOTES = [
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
    },
    {
        "page_id": "4",
        "quote": "Light from the surface filtered down through strategically placed shafts, creating patterns on the floor that changed with the seasons."
    },
    {
        "page_id": "5",
        "quote": "During the equinox, the entrance way's alignment causes a beam of light to illuminate the central altar for exactly seven minutes."
    },
    {
        "page_id": "6", 
        "quote": "Dr. Evelyn Thorne documented that the spiral shape was not arbitrary, but designed to create specific acoustic properties."
    },
    {
        "page_id": "7",
        "quote": "The narrowest part of the entrance way is called 'The Squeeze' and requires most adults to turn sideways to pass through."
    },
    {
        "page_id": "8",
        "quote": "Ancient markings on the walls suggest the original entrance was widened sometime in the 14th century."
    },
    {
        "page_id": "9",
        "quote": "Professor Arieol theorized that the spiral shape was meant to symbolize the journey from the outer world to inner knowledge."
    },
    {
        "page_id": "10",
        "quote": "The floor of the entrance way slopes downward at precisely 7 degrees, causing a disorienting effect as one descends."
    }
]

def generate_embedding(text: str) -> List[float]:
    """Generate random unit-normalized embedding vector"""
    vec = np.random.randn(VECTOR_DIM).astype(np.float32)
    vec = vec / np.linalg.norm(vec)
    return vec.tolist()

def main():
    # Create output directory
    output_dir = pathlib.Path(__file__).resolve().parent / "data"
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Generate embeddings for each quote
    quotes_with_embeddings = []
    vectors_dict = {}
    
    for quote_data in SAMPLE_QUOTES:
        page_id = quote_data["page_id"]
        quote = quote_data["quote"]
        
        # Generate random embedding
        embedding = generate_embedding(quote)
        
        # Save to quotes list
        quotes_with_embeddings.append({
            "page_id": page_id,
            "quote": quote,
            "embedding": embedding
        })
        
        # Save to vectors dictionary
        vectors_dict[page_id] = embedding
    
    # Save quotes to JSON
    quotes_file = output_dir / "quotes.json"
    with quotes_file.open("w") as f:
        json.dump(quotes_with_embeddings, f, indent=2)
    
    # Save vectors to JSON
    vectors_file = output_dir / "vectors.json"
    with vectors_file.open("w") as f:
        json.dump(vectors_dict, f, indent=2)
    
    logger.info(f"Generated {len(quotes_with_embeddings)} quotes with embeddings")
    logger.info(f"Saved quotes to {quotes_file}")
    logger.info(f"Saved vectors to {vectors_file}")

if __name__ == "__main__":
    main() 