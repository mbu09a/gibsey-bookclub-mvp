import sqlite3 # For type hinting Connection
from fastapi import Cookie, HTTPException, status, Depends
from typing import Annotated, Dict, Any, Optional

from core.session import verify_cookie
from core.db import get_db # Import the get_db dependency

def get_current_user(
    gibsey_sid: Annotated[Optional[str], Cookie()] = None, 
    db: sqlite3.Connection = Depends(get_db) # Inject DB connection
) -> Dict[str, Any]:
    """
    FastAPI dependency to get the current authenticated user based on the session cookie.
    Uses a request-scoped database connection.
    """
    if gibsey_sid is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated: No session cookie provided",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = verify_cookie(gibsey_sid)
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session cookie",
            headers={"WWW-Authenticate": "Bearer"},
        )

    db_cur = None
    try:
        db_cur = db.cursor() # Use the injected db connection
        db_cur.execute("SELECT id, email, name FROM users WHERE id=?", (user_id,))
        user_row = db_cur.fetchone()
    finally:
        if db_cur:
            db_cur.close()

    if not user_row:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found for valid session. Please login again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    return {"id": user_row[0], "email": user_row[1], "name": user_row[2]}

# For convenience when using with Depends, you might often see an alias:
# CurrentUser = Annotated[Dict[str, Any], Depends(get_current_user)]
# Then in your path operations: async def some_route(user: CurrentUser): 