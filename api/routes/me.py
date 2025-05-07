import sqlite3 # For type hinting Connection
from fastapi import APIRouter, Depends
from typing import Dict, Any

from core.auth import get_current_user # get_current_user itself now Depends on get_db
from core.ledger import get_balance
from core.db import get_db # Import get_db for direct use if needed, or rely on get_current_user's

router = APIRouter()

@router.get("/me", response_model=Dict[str, Any])
async def read_current_user_profile(
    current_user: Dict[str, Any] = Depends(get_current_user), # This will provide db to get_current_user
    db: sqlite3.Connection = Depends(get_db) # Also inject db here for get_balance
):
    """
    Fetches the current authenticated user's profile information, including their credit balance.
    """
    user_id = current_user.get("id")
    email = current_user.get("email")
    name = current_user.get("name")

    if user_id is None: # Should not happen if get_current_user dependency works
        return {"detail": "Could not identify user from session."}
        
    credit_balance = get_balance(db, user_id) # Pass the db connection to get_balance

    return {
        "id": user_id,
        "email": email,
        "name": name,
        "credits": credit_balance
    } 