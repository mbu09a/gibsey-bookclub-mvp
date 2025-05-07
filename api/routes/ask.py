from fastapi import APIRouter, Depends, Body
from typing import Dict, Any

from core.auth import get_current_user
from core.ledger import credit, get_balance # <--- Added get_balance

router = APIRouter()

# Define a Pydantic model for the request body if you want validation
# For now, using Body(...) with a Dict is simpler for the stub.
# class AskIn(BaseModel):
#     query: str

@router.post("/ask")
async def ask_question(
    payload: Dict[str, Any] = Body(...), # Expects {"query": "user question"}
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Handles a user's question. 
    For Day 3 MVP, this is a stub. It will later involve AI processing.
    """
    user_query = payload.get("query", "")
    user_id = current_user.get("id")

    # Placeholder: AI processing would happen here
    # For now, just echo the query and simulate some data
    simulated_answer = f'This is a placeholder answer from the Gibsey Guide regarding your query: "{user_query}".\n'
    simulated_answer += 'Later, this will include actual insights. For example, a relevant quote might be: '
    simulated_answer += '{"page_id":1, "loc":"p1-1", "quote":"Natalie stood before the doorway..."}.\n'
    simulated_answer += 'And another: {"page_id":2, "loc":"p2-1", "quote":"The brass knob was cold..."}.'

    new_balance = current_user.get('credits', 0) # Fallback, though /me should be source of truth
    if user_id:
        credit_success = credit(user_id, +1, "ask_question")
        if credit_success:
            new_balance = get_balance(user_id)
    else:
        print("Warning: User ID not found in current_user, cannot record credit for /ask")

    return {
        "answer": simulated_answer,
        "citations": [1, 2], # Placeholder page IDs for citations
        "credits": new_balance # Return the new balance
    } 