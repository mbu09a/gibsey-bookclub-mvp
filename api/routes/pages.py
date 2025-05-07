import json
import pathlib
from typing import Dict, Any, List

from fastapi import APIRouter, Depends, HTTPException, status
from core.auth import get_current_user # For authentication

router = APIRouter()

# Load page data when the module is imported - NOW FROM pages_710.json
DATA_FILE = pathlib.Path(__file__).parent.parent.parent / "data" / "pages_710.json" # <--- UPDATED FILENAME
PAGES_LIST: List[Dict[str, Any]] = []
PAGES_DICT: Dict[int, Dict[str, Any]] = {}
MAX_PAGE_ID = 0 # Initialize

try:
    with DATA_FILE.open("r", encoding="utf-8") as f:
        PAGES_LIST = json.load(f)
        for page in PAGES_LIST:
            if "id" in page:
                PAGES_DICT[page["id"]] = page
            else:
                print(f"Warning: Page missing 'id' in {DATA_FILE}: {page.get('title', 'Untitled')}")
    if not PAGES_LIST:
        print(f"Warning: {DATA_FILE} was loaded but is empty or contains no valid pages.")
    else:
        MAX_PAGE_ID = len(PAGES_LIST) # Correctly set MAX_PAGE_ID based on loaded pages
        # Alternatively, if IDs are not guaranteed sequential from 1 to N:
        # MAX_PAGE_ID = max(PAGES_DICT.keys()) if PAGES_DICT else 0
        print(f"Successfully loaded {len(PAGES_LIST)} pages (Max ID: {MAX_PAGE_ID}) from {DATA_FILE}")
except FileNotFoundError:
    print(f"ERROR: Page data file not found at {DATA_FILE}.")
except json.JSONDecodeError:
    print(f"ERROR: Could not decode JSON from {DATA_FILE}.")
except Exception as e:
    print(f"ERROR: An unexpected error occurred while loading pages from {DATA_FILE}: {e}")

@router.get("/page/{page_id}", response_model=Dict[str, Any])
async def get_page(
    page_id: int,
    current_user: Dict[str, Any] = Depends(get_current_user) # Protected route
):
    """Fetches a specific page by its ID."""
    if not PAGES_DICT: # Check if pages loaded correctly
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Page data is currently unavailable. Please try again later."
        )

    page = PAGES_DICT.get(page_id)
    if not page:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail=f"Page with id {page_id} not found. Max page ID is {MAX_PAGE_ID if MAX_PAGE_ID > 0 else 'N/A'}."
        )
    
    # Prepare the response, ensuring we don't leak unexpected fields if any
    return {
        "id": page.get("id"),
        "title": page.get("title"),
        "text": page.get("text"),
        "max_page_id": MAX_PAGE_ID # Send max page ID for frontend convenience
    } 