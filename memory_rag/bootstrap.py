#!/usr/bin/env python3
"""
Bootstrap utility for Memory RAG service

Loads all vectors from Stargate and initializes the FAISS index
Can be run directly or imported as a module
"""
import os
import sys
import time
import logging
import argparse
import json
import asyncio
import httpx
import pickle
import pathlib
import faiss
import numpy as np
from typing import Dict, List, Any, Optional, Tuple

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Default configuration
STARGATE_URL = os.getenv("STARGATE_URL", "http://stargate:8080")
STARGATE_TOKEN = os.getenv("STARGATE_AUTH_TOKEN", "")
KEYSPACE = os.getenv("KEYSPACE", "gibsey")
TABLE = os.getenv("TABLE", "page_vectors")
MEMORY_RAG_URL = os.getenv("MEMORY_RAG_URL", "http://localhost:8001")
DEFAULT_PAGE_SIZE = 100
DEFAULT_BATCH_SIZE = 50
DEFAULT_TIMEOUT = 30.0  # in seconds

# Local file paths for fallback
PROJECT_ROOT = pathlib.Path(__file__).resolve().parent
DATA_JSON_PATH = PROJECT_ROOT / "data" / "pages_710.json"  # Add this local file with the vectors
LOCAL_VECTORS_FILE = PROJECT_ROOT / "data" / "vectors.json"  # Can store sample vectors here

# Import here to avoid circular imports when used within the service
from indexer import vector_index, VectorStore, VECTOR_DIM

async def fetch_all_vectors(
    stargate_url: str = STARGATE_URL,
    keyspace: str = KEYSPACE,
    table: str = TABLE,
    stargate_token: str = STARGATE_TOKEN,
    page_size: int = DEFAULT_PAGE_SIZE,
    timeout: float = DEFAULT_TIMEOUT
) -> Dict[str, List[float]]:
    """
    Fetch all vectors from Stargate

    Args:
        stargate_url: Base URL for Stargate REST API
        keyspace: Cassandra keyspace name
        table: Table containing vectors
        stargate_token: Optional auth token
        page_size: Number of rows to fetch per page
        timeout: HTTP timeout in seconds

    Returns:
        Dictionary mapping page_ids to vectors
    """
    logger.info(f"Fetching vectors from {keyspace}.{table} via Stargate")

    vectors: Dict[str, List[float]] = {}

    async with httpx.AsyncClient(timeout=timeout) as client:
        url = f"{stargate_url}/v2/keyspaces/{keyspace}/{table}"
        headers = {}
        if stargate_token:
            headers["X-Cassandra-Token"] = stargate_token

        page_state = None
        total_fetched = 0

        while True:
            # Build request parameters
            params = {"page-size": page_size}
            if page_state:
                params["page-state"] = page_state

            try:
                logger.debug(f"Fetching page with state: {page_state}")
                response = await client.get(url, headers=headers, params=params)

                if response.status_code != 200:
                    logger.error(f"Failed to fetch vectors: {response.status_code} - {response.text}")
                    break

                data = response.json()
                rows = data.get("data", [])

                if not rows:
                    logger.info("No more rows to fetch")
                    break

                # Process this page of results
                for row in rows:
                    page_id = row.get("page_id")
                    vector = row.get("vector")

                    if page_id and vector and len(vector) == 768:
                        vectors[page_id] = vector
                        total_fetched += 1
                    else:
                        logger.warning(f"Skipped invalid vector for page_id: {page_id}")

                # Check if there are more pages
                page_state = data.get("pageState")
                if not page_state:
                    logger.info("No more pages to fetch")
                    break

                logger.info(f"Fetched {len(rows)} vectors, total so far: {total_fetched}")

            except httpx.HTTPError as e:
                logger.error(f"HTTP error during fetch: {str(e)}")
                break
            except Exception as e:
                logger.error(f"Error fetching vectors: {str(e)}")
                break

    logger.info(f"Successfully fetched {len(vectors)} vectors")
    return vectors

async def load_vectors_to_service(
    vectors: Dict[str, List[float]],
    memory_rag_url: str = MEMORY_RAG_URL,
    batch_size: int = DEFAULT_BATCH_SIZE,
    timeout: float = DEFAULT_TIMEOUT
) -> bool:
    """
    Load vectors into a running Memory RAG service by calling its API

    Args:
        vectors: Dictionary mapping page_ids to vectors
        memory_rag_url: Base URL of the Memory RAG service
        batch_size: Number of vectors to send in each request
        timeout: HTTP timeout in seconds

    Returns:
        True if successful, False otherwise
    """
    if not vectors:
        logger.warning("No vectors to load")
        return False

    refresh_endpoint = f"{memory_rag_url}/bulk-refresh"
    logger.info(f"Loading {len(vectors)} vectors into Memory RAG via {refresh_endpoint}")

    # Split into batches
    items = list(vectors.items())
    total_items = len(items)
    total_batches = (total_items + batch_size - 1) // batch_size
    success_count = 0

    async with httpx.AsyncClient(timeout=timeout) as client:
        for i in range(0, total_items, batch_size):
            batch = items[i:i+batch_size]
            batch_num = (i // batch_size) + 1

            try:
                # Prepare payload for each vector
                batch_payload = []
                for page_id, vector in batch:
                    batch_payload.append({
                        "page_id": page_id,
                        "vector": vector
                    })

                # Make bulk request
                logger.info(f"Sending batch {batch_num}/{total_batches} with {len(batch_payload)} vectors")
                response = await client.post(refresh_endpoint, json=batch_payload)

                if response.status_code == 202:
                    success_count += len(batch)
                    logger.info(f"Successfully loaded batch {batch_num}/{total_batches}")
                else:
                    logger.error(f"Failed to load batch {batch_num}: {response.status_code} - {response.text}")

            except httpx.HTTPError as e:
                logger.error(f"HTTP error during batch {batch_num}: {str(e)}")
            except Exception as e:
                logger.error(f"Error processing batch {batch_num}: {str(e)}")

    success_rate = success_count / total_items if total_items > 0 else 0
    logger.info(f"Loaded {success_count}/{total_items} vectors ({success_rate:.1%} success rate)")

    return success_count > 0

async def load_vectors_to_index(vectors: Dict[str, List[float]]) -> bool:
    """
    Load vectors directly into the in-memory FAISS index

    Args:
        vectors: Dictionary mapping page_ids to vectors

    Returns:
        True if successful, False otherwise
    """
    if not vectors:
        logger.warning("No vectors to load")
        return False

    try:
        logger.info(f"Loading {len(vectors)} vectors directly into FAISS index")

        # Clear existing index
        vector_index.clear()

        # Bulk load all vectors
        vector_index.bulk_add(vectors)

        # Log statistics
        stats = vector_index.get_stats()
        logger.info(f"Index loaded with {stats['total_vectors']} vectors")
        return True

    except Exception as e:
        logger.error(f"Failed to load vectors into index: {str(e)}")
        return False

async def bootstrap_memory_rag(
    stargate_url: str = STARGATE_URL,
    stargate_token: str = STARGATE_TOKEN,
    keyspace: str = KEYSPACE,
    table: str = TABLE,
    memory_rag_url: str = MEMORY_RAG_URL,
    page_size: int = DEFAULT_PAGE_SIZE,
    batch_size: int = DEFAULT_BATCH_SIZE,
    timeout: float = DEFAULT_TIMEOUT,
    direct_load: bool = True
) -> bool:
    """
    Bootstrap the Memory RAG service by loading all vectors from Stargate

    Args:
        stargate_url: Base URL for Stargate REST API
        stargate_token: Optional auth token
        keyspace: Cassandra keyspace name
        table: Table containing vectors
        memory_rag_url: Base URL of the Memory RAG service
        page_size: Number of rows to fetch per page from Stargate
        batch_size: Number of vectors to send in each refresh request
        timeout: HTTP timeout in seconds
        direct_load: If True, load directly to index; if False, call service API

    Returns:
        True if successful, False otherwise
    """
    logger.info(f"Starting bootstrap of Memory RAG from {stargate_url}/{keyspace}/{table}")
    start_time = time.time()

    try:
        # 1. Fetch all vectors from Stargate
        vectors = await fetch_all_vectors(
            stargate_url=stargate_url,
            keyspace=keyspace,
            table=table,
            stargate_token=stargate_token,
            page_size=page_size,
            timeout=timeout
        )

        if not vectors:
            logger.error("No vectors found in Stargate, bootstrap failed")
            return False

        # 2. Load vectors into Memory RAG
        if direct_load:
            # Load directly into the index (when run within the service)
            success = await load_vectors_to_index(vectors)
        else:
            # Load via the service API (when run as a standalone tool)
            success = await load_vectors_to_service(
                vectors=vectors,
                memory_rag_url=memory_rag_url,
                batch_size=batch_size,
                timeout=timeout
            )

        elapsed = time.time() - start_time
        logger.info(f"Bootstrap completed in {elapsed:.2f} seconds: {'success' if success else 'failed'}")
        return success

    except Exception as e:
        elapsed = time.time() - start_time
        logger.error(f"Bootstrap failed after {elapsed:.2f} seconds: {str(e)}")
        return False

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description="Bootstrap Memory RAG with vectors from Stargate")
    parser.add_argument("--stargate-url", default=STARGATE_URL, help="Stargate base URL")
    parser.add_argument("--stargate-token", default=STARGATE_TOKEN, help="Stargate auth token")
    parser.add_argument("--keyspace", default=KEYSPACE, help="Cassandra keyspace")
    parser.add_argument("--table", default=TABLE, help="Table containing vectors")
    parser.add_argument("--memory-rag-url", default=MEMORY_RAG_URL, help="Memory RAG service URL")
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE, help="Page size for Stargate requests")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE, help="Batch size for refresh requests")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="HTTP timeout in seconds")
    parser.add_argument("--direct", action="store_true", help="Load directly to index instead of via API")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose logging")
    return parser.parse_args()

async def main_async():
    """Async entry point"""
    args = parse_arguments()

    # Configure logging based on verbosity
    if args.verbose:
        logger.setLevel(logging.DEBUG)

    # Run bootstrap
    success = await bootstrap_memory_rag(
        stargate_url=args.stargate_url,
        stargate_token=args.stargate_token,
        keyspace=args.keyspace,
        table=args.table,
        memory_rag_url=args.memory_rag_url,
        page_size=args.page_size,
        batch_size=args.batch_size,
        timeout=args.timeout,
        direct_load=args.direct
    )

    # Exit with appropriate status code
    return 0 if success else 1

def main():
    """Command line entry point"""
    exit_code = asyncio.run(main_async())
    sys.exit(exit_code)

def fetch_vectors_from_stargate() -> Dict[str, List[float]]:
    """
    Fetch all vectors from Stargate API
    
    Returns:
        Dictionary mapping page_id to vector
    """
    vectors = {}
    next_page = None
    total_fetched = 0
    
    logger.info(f"Fetching vectors from {KEYSPACE}.{TABLE} via Stargate")
    
    try:
        while True:
            # Construct URL with pagination
            url = f"{STARGATE_URL}/v2/keyspaces/{KEYSPACE}/{TABLE}?page-size={DEFAULT_PAGE_SIZE}"
            if next_page:
                url = f"{next_page}"
                
            # Make request
            response = httpx.get(url)
            if response.status_code != 200:
                logger.error(f"Failed to fetch vectors: {response.status_code} - {response.text}")
                break
                
            # Parse response
            data = response.json()
            
            # Extract vectors
            for row in data.get("data", []):
                page_id = row.get("page_id")
                vector = row.get("vector")
                
                if page_id and vector:
                    vectors[page_id] = vector
                    total_fetched += 1
                    
            # Check if there are more pages
            next_page = data.get("pageState")
            if not next_page:
                break
                
    except Exception as e:
        logger.error(f"Error fetching vectors from Stargate: {e}")
        
    logger.info(f"Successfully fetched {total_fetched} vectors")
    return vectors

def generate_sample_vectors(count: int = 50) -> Dict[str, List[float]]:
    """
    Generate sample vectors for testing
    
    Args:
        count: Number of vectors to generate
        
    Returns:
        Dictionary mapping page_id to vector
    """
    vectors = {}
    
    for i in range(1, count + 1):
        # Generate random unit vector
        vec = np.random.randn(VECTOR_DIM).astype(np.float32)
        vec = vec / np.linalg.norm(vec)
        
        # Convert to list and add to dictionary
        vectors[str(i)] = vec.tolist()
        
    return vectors

def load_vectors_from_file() -> Dict[str, List[float]]:
    """
    Load vectors from local file as fallback
    
    Returns:
        Dictionary mapping page_id to vector
    """
    try:
        # Try to load from local vectors file first
        if LOCAL_VECTORS_FILE.exists():
            with LOCAL_VECTORS_FILE.open('r') as f:
                logger.info(f"Loading vectors from {LOCAL_VECTORS_FILE}")
                return json.load(f)
                
        # If that fails, try to parse the data JSON file with pages
        if DATA_JSON_PATH.exists():
            logger.info(f"Loading pages from {DATA_JSON_PATH}")
            with DATA_JSON_PATH.open('r') as f:
                pages = json.load(f)
                
            # Create vectors for each page (either from an embedding field or random)
            vectors = {}
            for page in pages:
                page_id = str(page.get('id', ''))
                
                if 'embedding' in page:
                    # Use existing embedding if available
                    vectors[page_id] = page['embedding']
                else:
                    # Generate random unit vector
                    vec = np.random.randn(VECTOR_DIM).astype(np.float32)
                    vec = vec / np.linalg.norm(vec)
                    vectors[page_id] = vec.tolist()
                    
            logger.info(f"Generated {len(vectors)} vectors from local pages file")
            
            # Save for future use
            with LOCAL_VECTORS_FILE.open('w') as f:
                json.dump(vectors, f)
                
            return vectors
            
    except Exception as e:
        logger.error(f"Error loading vectors from file: {e}")
        
    # If all else fails, generate sample vectors
    logger.info("Generating sample vectors as fallback")
    return generate_sample_vectors(50)

if __name__ == "__main__":
    main()