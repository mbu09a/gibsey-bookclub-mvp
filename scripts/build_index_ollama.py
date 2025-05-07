import json
import pathlib
import pickle
import requests
import faiss
import numpy as np
import sys

print("Starting index build...")

# Define project root assuming this script is in /scripts/
PROJECT_ROOT = pathlib.Path(__file__).parent.parent
DATA_JSON = PROJECT_ROOT / "data" / "pages_100w.json"
INDEX_FILE = PROJECT_ROOT / "data" / "page_vectors.faiss"
META_FILE = PROJECT_ROOT / "data" / "page_meta.pkl"
OLLAMA_API = "http://localhost:11434/api/embeddings"
EMBED_MODEL = "nomic-embed-text"

if not DATA_JSON.exists():
    print(f"ERROR: Source data file not found at {DATA_JSON}. Cannot build index.")
    sys.exit(1)

pages = []
try:
    print(f"Loading pages from {DATA_JSON}...")
    with DATA_JSON.open("r", encoding="utf-8") as f:
        pages = json.load(f)
    print(f"Loaded {len(pages)} pages.")
except Exception as e:
    print(f"ERROR: Failed to load or parse {DATA_JSON}: {e}")
    sys.exit(1)

vecs = []
page_ids_in_order = [] # Store the page IDs corresponding to the vectors

print(f"Generating embeddings using Ollama model '{EMBED_MODEL}'...")
# --- Loop through pages and get embeddings --- 
for i, p in enumerate(pages):
    page_id = p.get("id")
    page_text = p.get("text")
    
    if page_id is None or page_text is None:
        print(f"Warning: Skipping page index {i} due to missing id or text.")
        continue

    try:
        payload = {"model": EMBED_MODEL, "prompt": page_text}
        response = requests.post(OLLAMA_API, json=payload)
        response.raise_for_status() # Raise HTTPError for bad responses (4xx or 5xx)
        
        embedding = response.json().get("embedding")
        if embedding:
            vecs.append(embedding)
            page_ids_in_order.append(page_id)
        else:
            print(f"Warning: No embedding returned for page id {page_id}.")
        
        # Print progress indicator
        if (i + 1) % 50 == 0:
             print(f"  Processed {i + 1}/{len(pages)} pages...")

    except requests.exceptions.ConnectionError:
        print(f"\nERROR: Connection to Ollama API ({OLLAMA_API}) failed. Is 'ollama serve' running?")
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"\nERROR: Request to Ollama API failed for page id {page_id}: {e}")
        # Optionally continue to next page or exit based on desired robustness
        # For now, we exit if any API call fails after the first connection.
        sys.exit(1)
    except Exception as e:
        print(f"\nERROR: An unexpected error occurred processing page id {page_id}: {e}")
        sys.exit(1)

if not vecs:
    print("ERROR: No embeddings were generated. Cannot build index.")
    sys.exit(1)

print(f"Generated {len(vecs)} embeddings.")

# --- Build and save FAISS index --- 
try:
    print("Converting embeddings to numpy array...")
    embeds = np.asarray(vecs, dtype="float32")
    print("Normalizing embeddings...")
    faiss.normalize_L2(embeds) # Normalize for cosine similarity using IndexFlatIP
    
    dimension = embeds.shape[1]
    print(f"Building FAISS index (IndexFlatIP) with dimension {dimension}...")
    index = faiss.IndexFlatIP(dimension) # Using Inner Product (IP) for similarity on normalized vectors (cosine similarity)
    index.add(embeds)
    
    print(f"Writing FAISS index to {INDEX_FILE}...")
    faiss.write_index(index, str(INDEX_FILE))
    
    print(f"Writing page ID metadata to {META_FILE}...")
    with META_FILE.open("wb") as f:
        pickle.dump(page_ids_in_order, f)

    print(f"\nSuccessfully indexed {index.ntotal} pages.")
    print(f"Index saved to: {INDEX_FILE}")
    print(f"Metadata saved to: {META_FILE}")

except Exception as e:
    print(f"\nERROR: Failed to build or save FAISS index / metadata: {e}")
    sys.exit(1) 