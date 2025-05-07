import time
import sqlite3
from fastapi import APIRouter, Depends, HTTPException, status, Body
from typing import Dict, Any, List, Optional

from core.auth import get_current_user
from core.db import con # Using the shared connection
# Import PAGES_DICT from pages router to get page titles
# This creates a dependency between these modules. Consider if a shared data service would be better for a larger app.
from api.routes.pages import PAGES_DICT 
# from core.ledger import credit, get_balance # For optional credit earning on save

router = APIRouter()

class VaultSaveIn(Dict[Any, Any]): # Using Dict for Body, could be Pydantic model
    page_id: int
    note: Optional[str] = ""

@router.post("/save", status_code=status.HTTP_201_CREATED)
async def save_passage_to_vault(
    payload: VaultSaveIn = Body(...),
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """Saves a page to the current user's vault."""
    user_id = current_user.get("id")
    page_id = payload.get("page_id")
    note = payload.get("note", "")
    current_timestamp = int(time.time())

    if not isinstance(page_id, int):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="page_id must be an integer.")

    if page_id not in PAGES_DICT:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Page with id {page_id} does not exist and cannot be saved.")

    db_cur = None
    try:
        db_cur = con.cursor()
        db_cur.execute(
            "INSERT INTO vault (user_id, page_id, note, ts) VALUES (?, ?, ?, ?)",
            (user_id, page_id, note, current_timestamp)
        )
        con.commit()
        
        # Optional: Award credit for saving (implement as per Day 5 plan)
        # credit_awarded = credit(user_id, +1, "save_passage")
        # new_balance = get_balance(user_id) if credit_awarded else None

        return {
            "ok": True, 
            "message": f"Page {page_id} saved to vault.",
            # "new_credits": new_balance # Optionally return new credits
        }
    except sqlite3.IntegrityError: # Catches UNIQUE constraint violation (user_id, page_id)
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Page {page_id} is already in your vault."
        )
    except Exception as e:
        # con.rollback() # Consider if needed
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
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """Lists all passages saved in the current user's vault."""
    user_id = current_user.get("id")
    db_cur = None
    try:
        db_cur = con.cursor()
        # Fetch vault entries along with page titles by joining/looking up
        # For this version, we fetch from vault and then lookup title in PAGES_DICT
        db_cur.execute(
            "SELECT id, page_id, note, ts FROM vault WHERE user_id = ? ORDER BY ts DESC",
            (user_id,)
        )
        raw_entries = db_cur.fetchall()
        
        vault_entries = []
        for entry in raw_entries:
            page_info = PAGES_DICT.get(entry[1]) # entry[1] is page_id
            title = page_info.get("title", "Unknown Title") if page_info else "Page data not found"
            vault_entries.append({
                "id": entry[0], # Vault entry ID
                "page_id": entry[1],
                "note": entry[2],
                "ts": entry[3],
                "title": title
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