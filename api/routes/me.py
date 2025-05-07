from fastapi import APIRouter, Depends
from typing import Dict, Any

from core.auth import get_current_user
from core.ledger import get_balance

router = APIRouter()

@router.get("/me", response_model=Dict[str, Any])
async def read_current_user_profile(
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Fetches the current authenticated user's profile information, including their credit balance.
    """
    user_id = current_user.get("id")
    email = current_user.get("email")
    name = current_user.get("name")

    if user_id is None: # Should not happen if get_current_user dependency works
        return {"detail": "Could not identify user from session."}
        
    credit_balance = get_balance(user_id)

    return {
        "id": user_id,
        "email": email,
        "name": name,
        "credits": credit_balance
    } 