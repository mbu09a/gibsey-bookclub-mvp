"""
Memory RAG FastAPI service

This service provides semantic retrieval over book pages using FAISS vector search and
embedding-based retrieval. It loads vectors from Stargate, maintains a FAISS index in memory,
and responds to queries with relevant page quotes.
"""
from fastapi import FastAPI, HTTPException, Depends, BackgroundTasks, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, ConfigDict
import httpx
import os
import re
import time
import asyncio
import logging
import json
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime

# Local imports
from indexer import vector_index
from slice_logic import extract_relevant_quotes
from prometheus_fastapi_instrumentator import Instrumentator

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Environment variables
STARGATE_URL = os.getenv("STARGATE_URL", "http://stargate:8080")
STARGATE_TOKEN = os.getenv("STARGATE_AUTH_TOKEN", "")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama:11434")
EMBED_MODEL = os.getenv("EMBED_MODEL", "nomic-embed-text")
VERSION = os.getenv("VERSION", "1.0.0")
SERVICE_NAME = "memory-rag"

# Embedding URL derived from OLLAMA_URL
EMBED_URL = f"{OLLAMA_URL}/api/embeddings"

# Initialize FastAPI
app = FastAPI(
    title="Gibsey Memory RAG",
    description="Semantic search and retrieval over book content",
    version=VERSION
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add metrics endpoint via Prometheus instrumentator
Instrumentator().instrument(app).expose(app)

# Request/response models
class RefreshBody(BaseModel):
    """Request body for refreshing a single vector"""
    page_id: str
    vector: List[float] = Field(min_items=768, max_items=768)

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "page_id": "page-123",
                "vector": [0.1, 0.2, 0.3, 0.4, 0.5] + [0.0] * 763  # 768 total dimensions
            }
        }
    )

class VectorItem(BaseModel):
    """A single vector item for bulk operations"""
    page_id: str
    vector: List[float]

class RetrieveResult(BaseModel):
    """A single retrieval result with page ID and quote"""
    page_id: str
    quote: str
    score: float
    word_count: int

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "page_id": "page-123",
                "quote": "The mysterious figure approached from the shadows, eyes gleaming with ancient knowledge.",
                "score": 0.87,
                "word_count": 12
            }
        }
    )

class StatsResponse(BaseModel):
    """Response model for vector index statistics"""
    total_vectors: int
    dimension: int
    index_type: str
    memory_usage_bytes: int
    unique_page_ids: int
    last_updated: str
    uptime_seconds: float

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "total_vectors": 710,
                "dimension": 768,
                "index_type": "IndexFlatIP",
                "memory_usage_bytes": 2179200,
                "unique_page_ids": 710,
                "last_updated": "2023-09-22T15:30:45.123456",
                "uptime_seconds": 3600.5
            }
        }
    )

class VersionInfo(BaseModel):
    """Response model for version information"""
    service: str
    version: str
    api_version: str
    faiss_vectors: int

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "service": "memory-rag",
                "version": "1.0.0",
                "api_version": "v1",
                "faiss_vectors": 710
            }
        }
    )

# Global state
start_time = time.time()
last_updated = datetime.now().isoformat()

# Embedding utility
async def embed_text(text: str) -> List[float]:
    """
    Generate embedding vector for text using Ollama

    Args:
        text: Text to embed

    Returns:
        List of 768 floats representing the embedding vector

    Raises:
        HTTPException: If embedding service cannot be reached
    """
    try:
        async with httpx.AsyncClient() as client:
            logger.debug(f"Embedding text of length {len(text)}")
            response = await client.post(
                EMBED_URL,
                json={"model": EMBED_MODEL, "prompt": text},
                timeout=30.0  # Long timeout for first inference
            )
            response.raise_for_status()
            data = response.json()

            embedding = data.get("embedding")
            if not embedding or len(embedding) != 768:
                logger.error(f"Invalid embedding response. Expected 768 dimensions, got {len(embedding) if embedding else 0}")
                raise HTTPException(status_code=500, detail="Invalid embedding response from model")

            return embedding
    except httpx.HTTPError as e:
        logger.error(f"HTTP error while generating embedding: {e}")
        raise HTTPException(status_code=503, detail=f"Embedding service unavailable: {str(e)}")
    except Exception as e:
        logger.error(f"Error generating embedding: {e}")
        raise HTTPException(status_code=500, detail=f"Embedding service error: {str(e)}")

async def fetch_page_content(page_id: str) -> Optional[str]:
    """
    Fetch page content from Stargate

    Args:
        page_id: The ID of the page to fetch

    Returns:
        Page body text or None if not found
    """
    try:
        async with httpx.AsyncClient() as client:
            url = f"{STARGATE_URL}/v2/keyspaces/gibsey/pages/{page_id}"
            headers = {}
            if STARGATE_TOKEN:
                headers["X-Cassandra-Token"] = STARGATE_TOKEN

            response = await client.get(url, headers=headers, timeout=5.0)
            if response.status_code == 404:
                logger.warning(f"Page {page_id} not found in Stargate")
                return None

            response.raise_for_status()
            page_data = response.json()
            return page_data.get("body", "")
    except httpx.HTTPError as e:
        logger.error(f"HTTP error fetching page {page_id}: {e}")
        return None
    except Exception as e:
        logger.error(f"Error fetching page {page_id}: {e}")
        return None

# API Endpoints
@app.post("/refresh", status_code=202,
         summary="Refresh a single vector in the index",
         description="Update or add a vector to the in-memory FAISS index. Called by the Kafka consumer when a page is updated.")
async def refresh(row: RefreshBody):
    """
    Update the vector index with a new/updated page vector.
    Called by the Kafka consumer when a page is updated.
    """
    global last_updated
    vector_index.add_vector(row.page_id, row.vector)
    last_updated = datetime.now().isoformat()
    return {"status": "ok", "page_id": row.page_id}

@app.get("/retrieve", response_model=List[RetrieveResult],
        summary="Retrieve relevant passages from pages",
        description="Embeds the query text, finds semantically similar vectors, and returns relevant quotes")
async def retrieve(
    q: str = Query(..., description="The search query", min_length=2),
    k: int = Query(4, description="Number of results to return", ge=1, le=10)
):
    """
    Retrieve the most relevant quotes from pages matching the query.

    Args:
        q: The query text
        k: Number of results to return (default: 4)

    Returns:
        List of page_id/quote pairs sorted by relevance
    """
    # Track performance
    start = time.time()

    # 1. Generate embedding for the query
    query_vector = await embed_text(q)

    # 2. Search for similar vectors
    similar_pages = vector_index.search(query_vector, k)

    if not similar_pages:
        logger.warning(f"No matching pages found for query: {q}")
        return []

    # 3. Fetch the content of matching pages
    results = []
    for page_id, score in similar_pages:
        try:
            # Fetch page content from Stargate
            page_content = await fetch_page_content(page_id)
            if not page_content:
                continue

            # 4. Extract the most relevant quotes
            quotes = extract_relevant_quotes(page_content, q)

            if quotes:
                best_quote = quotes[0]  # Get the highest scoring quote
                results.append({
                    "page_id": page_id,
                    "quote": best_quote["quote"],
                    "score": best_quote["score"],
                    "word_count": best_quote["word_count"]
                })
        except Exception as e:
            logger.error(f"Error processing page {page_id}: {e}")

    # Log performance metrics
    elapsed = time.time() - start
    logger.info(f"Retrieved {len(results)} results for query '{q}' in {elapsed:.3f}s")

    return results

@app.get("/stats", response_model=StatsResponse,
        summary="Get index statistics",
        description="Returns statistics about the FAISS vector index")
async def stats():
    """Get statistics about the vector index."""
    global start_time, last_updated
    uptime = time.time() - start_time

    stats = vector_index.get_stats()
    stats["last_updated"] = last_updated
    stats["uptime_seconds"] = uptime

    return stats

@app.post("/bootstrap", status_code=202,
         summary="Bootstrap the vector index",
         description="Load all vectors from Stargate into the in-memory FAISS index")
async def bootstrap(background_tasks: BackgroundTasks):
    """
    Bootstrap the index by loading all page vectors from Cassandra.
    This is called on service startup or if the index needs to be rebuilt.
    """
    background_tasks.add_task(_bootstrap_index)
    return {"status": "Bootstrap started in the background"}

@app.get("/version", response_model=VersionInfo,
        summary="Get service version",
        description="Returns version information about the service")
async def version():
    """Get service version information."""
    return {
        "service": SERVICE_NAME,
        "version": VERSION,
        "api_version": "v1",
        "faiss_vectors": vector_index.index.ntotal
    }

@app.get("/health",
        summary="Health check endpoint",
        description="Returns health status of the service")
async def health():
    """Health check endpoint."""
    global start_time
    uptime = time.time() - start_time

    index_size = vector_index.index.ntotal
    status = "healthy" if index_size > 0 else "degraded"

    return JSONResponse(
        status_code=200 if status == "healthy" else 207,
        content={
            "status": status,
            "index_size": index_size,
            "uptime": uptime,
            "last_updated": last_updated
        }
    )

async def _bootstrap_index():
    """Background task to bootstrap the index from Stargate."""
    logger.info("Starting bootstrap of vector index")

    # Clear the existing index
    vector_index.clear()

    # Fetch vectors from Cassandra via Stargate API
    async with httpx.AsyncClient() as client:
        url = f"{STARGATE_URL}/v2/keyspaces/gibsey/page_vectors"
        headers = {}
        if STARGATE_TOKEN:
            headers["X-Cassandra-Token"] = STARGATE_TOKEN

        try:
            page_size = 100
            page_state = None
            total_vectors = 0
            batch = {}

            while True:
                params = {"page-size": page_size}
                if page_state:
                    params["page-state"] = page_state

                response = await client.get(url, headers=headers, params=params, timeout=10.0)
                if response.status_code != 200:
                    logger.error(f"Failed to fetch vectors: {response.status_code}")
                    break

                data = response.json()
                vectors = data.get("data", [])
                if not vectors:
                    break

                # Collect vectors for bulk insertion
                for row in vectors:
                    page_id = row.get("page_id")
                    vector = row.get("vector")
                    if page_id and vector and len(vector) == 768:
                        batch[page_id] = vector
                        total_vectors += 1

                # Check if there are more pages
                page_state = data.get("pageState")
                if not page_state:
                    break

            # Bulk add all vectors
            if batch:
                vector_index.bulk_add(batch)

            global last_updated
            last_updated = datetime.now().isoformat()
            logger.info(f"Bootstrap complete. Loaded {total_vectors} vectors.")

        except Exception as e:
            logger.error(f"Error during bootstrap: {e}")

@app.on_event("startup")
async def startup_event():
    """Run when the service starts up."""
    global start_time
    start_time = time.time()

    logger.info(f"Memory RAG service v{VERSION} starting up")
    logger.info(f"STARGATE_URL: {STARGATE_URL}")
    logger.info(f"OLLAMA_URL: {OLLAMA_URL}")
    logger.info(f"EMBED_MODEL: {EMBED_MODEL}")

    # Bootstrap the index in the background
    asyncio.create_task(_bootstrap_index())

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8001, reload=True)