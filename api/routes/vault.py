import time
import sqlite3
from fastapi import APIRouter, Depends, HTTPException, status, Body
from typing import Dict, Any, List, Optional
from pydantic import BaseModel

from core.auth import get_current_user
from core.db import get_db # Import get_db for direct use
from api.routes.pages import PAGES_DICT
from core.ledger import credit, get_balance # <--- Import credit and get_balance

router = APIRouter()

class VaultSaveIn(BaseModel): # <--- Changed to inherit from BaseModel
    page_id: int
    note: Optional[str] = ""

# Optional: Define a response model for clarity, though Dict[str, Any] also works
class VaultSaveOut(BaseModel):
    ok: bool
    message: str
    new_credits: Optional[int] = None # <--- Added new_credits field

@router.post("/save", status_code=status.HTTP_201_CREATED, response_model=VaultSaveOut) # <--- Added response_model
async def save_passage_to_vault(
    payload: VaultSaveIn, # <--- No need for Body(...) when using Pydantic model directly
    current_user: Dict[str, Any] = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db) # Inject DB connection
):
    """Saves a page to the current user's vault."""
    user_id = current_user.get("id")
    # page_id and note are now accessed via Pydantic model attributes
    page_id = payload.page_id
    note = payload.note
    current_timestamp = int(time.time())

    # Re-enabled: Check if page_id exists in our loaded page data
    if page_id not in PAGES_DICT:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Page with id {page_id} does not exist and cannot be saved.")

    db_cur = None
    new_balance = None # Initialize
    try:
        db_cur = db.cursor()
        db_cur.execute(
            "INSERT INTO vault (user_id, page_id, note, ts) VALUES (?, ?, ?, ?)",
            (user_id, page_id, note, current_timestamp)
        )
        # db.commit() will be called after attempting to award credit

        # Award credit for saving
        if user_id: # Should always be true due to Depends(get_current_user)
            credit_awarded = credit(db, user_id, +1, "save_passage") # Pass db connection
            if credit_awarded:
                new_balance = get_balance(db, user_id) # Pass db connection
            else:
                # Decide if saving to vault should fail if credit awarding fails
                # For now, we'll assume vault save is primary, credit is secondary
                print(f"Warning: Vault entry saved for user {user_id}, page {page_id}, but failed to award credit.")
        
        db.commit() # Commit both vault save and ledger entry (if successful)
        
        return VaultSaveOut(ok=True, message=f"Page {page_id} saved to vault.", new_credits=new_balance)
    except sqlite3.IntegrityError: # Catches UNIQUE constraint violation (user_id, page_id)
        # db.rollback() # Not strictly necessary for a single insert that fails constraint
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Page {page_id} is already in your vault."
        )
    except Exception as e:
        # db.rollback()
        print(f"Error saving page to vault for user {user_id}, page {page_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while saving to vault."
        )
    finally:
        if db_cur:
            db_cur.close()

@router.get("", response_model=List[Dict[str, Any]]) # GET /vault returns a list
async def list_vault_entries(
    current_user: Dict[str, Any] = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db) # Inject DB connection
):
    """Lists all passages saved in the current user's vault."""
    user_id = current_user.get("id")
    db_cur = None
    try:
        db_cur = db.cursor()
        # Fetch vault entries along with page titles by joining/looking up
        # For this version, we fetch from vault and then lookup title in PAGES_DICT
        db_cur.execute(
            "SELECT id, page_id, note, ts FROM vault WHERE user_id = ? ORDER BY ts DESC",
            (user_id,)
        )
        raw_entries = db_cur.fetchall()
        
        vault_entries = []
        for entry in raw_entries:
            page_info = PAGES_DICT.get(entry[1])
            title = page_info.get("title", "Unknown Title") if page_info else "Page data not found"
            vault_entries.append({
                "id": entry[0], # Vault entry ID
                "page_id": entry[1],
                "note": entry[2],
                "ts": entry[3],
                "title": title # <--- Use actual title
            })
        return vault_entries
    except Exception as e:
        print(f"Error fetching vault for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while fetching vault entries."
        )
    finally:
        if db_cur:
            db_cur.close() 