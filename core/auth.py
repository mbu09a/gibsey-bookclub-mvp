from fastapi import Cookie, HTTPException, status, Depends
from typing import Annotated, Dict, Any # For type hinting

from core.session import verify_cookie
from core.db import con, cur # Import shared connection and cursor

def get_current_user(gibsey_sid: Annotated[str | None, Cookie()] = None) -> Dict[str, Any]:
    """
    FastAPI dependency to get the current authenticated user based on the session cookie.
    Raises HTTPException with 401 status if authentication fails.
    """
    if gibsey_sid is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated: No session cookie provided",
            headers={"WWW-Authenticate": "Bearer"}, # Though we use cookies, good practice
        )

    user_id = verify_cookie(gibsey_sid)
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session cookie",
            headers={"WWW-Authenticate": "Bearer"},
        )

    cur.execute("SELECT id, email, name FROM users WHERE id=?", (user_id,))
    user_row = cur.fetchone()

    if not user_row:
        # This case should ideally not happen if a valid user_id was in the cookie
        # and the user exists in the database. Could indicate DB inconsistency or stale cookie.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found for valid session. Please login again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    return {"id": user_row[0], "email": user_row[1], "name": user_row[2]}

# For convenience when using with Depends, you might often see an alias:
# CurrentUser = Annotated[Dict[str, Any], Depends(get_current_user)]
# Then in your path operations: async def some_route(user: CurrentUser): 