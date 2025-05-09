import sqlite3 # For type hinting Connection
from fastapi import APIRouter, Depends, Body, HTTPException, status
from typing import Dict, Any, List
import requests
import httpx
import numpy as np
import faiss
import pickle
import json
import pathlib

from core.auth import get_current_user
from core.ledger import credit, get_balance
from core.db import get_db # Import get_db for direct use

router = APIRouter()

# --- RAG Configuration --- 
OLLAMA_API = "http://localhost:11434/api" # Base Ollama API URL
EMBED_MODEL = "nomic-embed-text"
GENERATION_MODEL = "llama3" # Assumes llama3 is pulled via ollama

PROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
DATA_JSON_PATH = PROJECT_ROOT / "data" / "pages_710.json"
INDEX_PATH = PROJECT_ROOT / "data" / "page_vectors.faiss"
META_PATH = PROJECT_ROOT / "data" / "page_meta.pkl"

# --- Load RAG components --- 
PAGES_DICT: Dict[int, Dict[str, Any]] = {}
try:
    with DATA_JSON_PATH.open("r", encoding="utf-8") as f:
        _pages_list = json.load(f)
        PAGES_DICT = {p["id"]: p for p in _pages_list if "id" in p}
    print(f"RAG (ask.py): Loaded {len(PAGES_DICT)} pages from {DATA_JSON_PATH}.")
except Exception as e:
    print(f"RAG ERROR (ask.py): Failed to load {DATA_JSON_PATH}: {e}")

try:
    print(f"RAG: Loading FAISS index from {INDEX_PATH}...")
    faiss_index = faiss.read_index(str(INDEX_PATH))
    print(f"RAG: FAISS index loaded with {faiss_index.ntotal} vectors.")
except Exception as e:
    print(f"RAG ERROR: Failed to load FAISS index {INDEX_PATH}: {e}")
    faiss_index = None

try:
    print(f"RAG: Loading metadata from {META_PATH}...")
    with META_PATH.open("rb") as f:
        page_ids_in_order = pickle.load(f)
    print(f"RAG: Metadata loaded mapping {len(page_ids_in_order)} indices to page IDs.")
except Exception as e:
    print(f"RAG ERROR: Failed to load metadata {META_PATH}: {e}")
    page_ids_in_order = []
# --------------------------

def embed_text(text: str) -> np.ndarray:
    """Generates embedding for text using Ollama."""
    try:
        response = requests.post(f"{OLLAMA_API}/embeddings", json={"model": EMBED_MODEL, "prompt": text})
        response.raise_for_status()
        embedding = response.json().get("embedding")
        if not embedding:
            raise ValueError("No embedding returned from Ollama")
        
        vector = np.asarray(embedding, dtype="float32").reshape(1, -1)
        faiss.normalize_L2(vector) # Normalize for cosine similarity
        return vector
    except Exception as e:
        print(f"Error getting embedding from Ollama: {e}")
        raise  # Re-raise the exception to be caught by the caller

def find_top_pages(query_vector: np.ndarray, k: int = 3) -> List[int]:
    """Searches the FAISS index for top K similar pages."""
    if not faiss_index or not page_ids_in_order or faiss_index.ntotal != len(page_ids_in_order):
        print("Error: FAISS index or metadata not loaded correctly.")
        return []
    try:
        distances, indices = faiss_index.search(query_vector, k)
        # indices[0] contains the indices of the top k vectors
        return [page_ids_in_order[i] for i in indices[0] if i >= 0 and i < len(page_ids_in_order)]
    except Exception as e:
        print(f"Error searching FAISS index: {e}")
        return []

def generate_answer(query: str, context: str) -> str:
    """Generates an answer using Ollama based on query and context."""
    prompt = f"""Based on the following context from 'The Entrance Way', answer the user's question. 
Be concise and directly answer the question using information primarily from the context provided. 
If the context doesn't provide an answer, say you couldn't find an answer in the provided text.

Context:
{context}

User Question: {query}

Answer:"""
    
    try:
        response = requests.post(
            f"{OLLAMA_API}/generate", 
            json={
                "model": GENERATION_MODEL,
                "prompt": prompt,
                "stream": False # Get the full response at once
            }
        )
        response.raise_for_status()
        # Assuming response format has a 'response' key with the generated text
        return response.json().get("response", "Error: Could not get generated response from Ollama.")
    except Exception as e:
        print(f"Error generating answer from Ollama ({GENERATION_MODEL}): {e}")
        return f"Error generating answer: {e}"

@router.post("/ask", response_model=Dict[str, Any]) # Define response model later if needed
async def ask_question(
    payload: Dict[str, Any] = Body(...),
    current_user: Dict[str, Any] = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    user_query = payload.get("query", "")
    char_id = payload.get("char_id", "")
    text = payload.get("text", "")
    user_id = current_user.get("id")
    
    # Use text if provided, otherwise use query
    query_text = text or user_query
    
    if not query_text:
        raise HTTPException(status_code=400, detail="Query cannot be empty.")

    try:
        # Get relevant quotes from Memory RAG service
        resp = httpx.get("http://localhost:8001/retrieve", params={"q": query_text, "k": 4})
        if resp.status_code != 200:
            raise HTTPException(status_code=503, detail="Could not connect to Memory RAG service.")
            
        retrieved_quotes = resp.json()
        
        # Format quotes for context
        quotes = [f"- {row['quote']} (p.{row['page_id']})" for row in retrieved_quotes]
        context = "\n".join(quotes)
        
        if not context:
            print(f"No relevant context found for query: '{query_text}'")
            final_answer = "I couldn't find any relevant passages in the text to answer that question."
        else:
            # Generate answer using LLM with the quotes as context
            print(f"Generating answer for query: '{query_text}' with {len(quotes)} quotes")
            
            # Build prompt with quotes
            prompt = f"""Based on the following excerpts from 'The Entrance Way', answer the user's question. 
Use the provided quotes to ground your answer. If you cite information, include the page number in parentheses.

Relevant Quotes:
{context}

User Question: {query_text}

Answer:"""
            
            # Call Ollama for generation
            response = requests.post(
                f"{OLLAMA_API}/generate", 
                json={
                    "model": GENERATION_MODEL,
                    "prompt": prompt,
                    "stream": False # Get the full response at once
                }
            )
            response.raise_for_status()
            final_answer = response.json().get("response", "Error: Could not get generated response from Ollama.")

        # Award credit
        new_balance = current_user.get('credits', 0)
        if user_id:
            credit_success = credit(db, user_id, +1, "ask_question")
            if credit_success:
                new_balance = get_balance(db, user_id)
        else:
            print("Warning: User ID not found, cannot record credit for /ask")

        return {
            "answer": final_answer,
            "citations": [quote['page_id'] for quote in retrieved_quotes], 
            "credits": new_balance 
        }

    except Exception as e:
        print(f"Error during /ask for query '{query_text}': {e}")
        # Consider more specific error handling based on where exception occurred (embedding, search, generation)
        raise HTTPException(status_code=500, detail=f"An error occurred processing your request: {e}")

@router.get("/test-rag", response_model=Dict[str, Any])
async def test_rag_integration(query: str = "Why is the entrance way spiral-shaped?"):
    """Test endpoint for Memory RAG integration without authentication"""
    try:
        # Get relevant quotes from Memory RAG service
        resp = httpx.get("http://localhost:8001/retrieve", params={"q": query, "k": 4})
        if resp.status_code != 200:
            return {"error": f"Could not connect to Memory RAG service: {resp.status_code}"}
            
        retrieved_quotes = resp.json()
        
        # Format quotes for context
        quotes = [f"- {row['quote']} (p.{row['page_id']})" for row in retrieved_quotes]
        context = "\n".join(quotes)
        
        return {
            "success": True,
            "quotes": retrieved_quotes,
            "context": context
        }

    except Exception as e:
        return {"error": f"Error during test: {str(e)}"} 