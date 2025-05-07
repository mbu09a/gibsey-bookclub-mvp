import sqlite3 # For type hinting Connection
from fastapi import Cookie, HTTPException, status, Depends, Request
from typing import Annotated, Dict, Any, Optional

from core.session import verify_cookie
from core.db import get_db # Import the get_db dependency

def get_current_user(
    request: Request,
    gibsey_sid: Annotated[Optional[str], Cookie()] = None, 
    db: sqlite3.Connection = Depends(get_db) # Inject DB connection
) -> Dict[str, Any]:
    """
    FastAPI dependency to get the current authenticated user based on the session cookie.
    Uses a request-scoped database connection.
    """
    if gibsey_sid is None:
        # If no session cookie, but also no seen_welcome cookie, redirect to welcome.
        # This case handles users who are not logged in AND haven't seen welcome.
        if not request.cookies.get("seen_welcome"):
            raise HTTPException(
                status_code=status.HTTP_307_TEMPORARY_REDIRECT,
                detail="New user, redirecting to welcome.",
                headers={"Location": "/api/v1/onboard/welcome"} # Adjusted to full path
            )
        # If no session, but they HAVE seen welcome, then it's a normal unauthorized.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated: No session cookie provided",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = verify_cookie(gibsey_sid)
    if not user_id:
        # Invalid/expired session. If they haven't seen welcome, still send to welcome.
        if not request.cookies.get("seen_welcome"):
            raise HTTPException(
                status_code=status.HTTP_307_TEMPORARY_REDIRECT,
                detail="Invalid session, redirecting to welcome.",
                headers={"Location": "/api/v1/onboard/welcome"}
            )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session cookie",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Valid session, now check for seen_welcome for logged-in users hitting a protected route for the first time
    # in a session where seen_welcome might not have been set (e.g. cookie cleared, but session still valid)
    # This logic primarily applies if a protected route is hit before App.jsx can make its own routing decisions.
    if not request.cookies.get("seen_welcome"):
        # If they are logged in but somehow missed the welcome flow (e.g. direct nav to protected API)
        # it's often better to let the frontend app (App.jsx) handle the welcome redirect logic
        # based on its own state after /me call, rather than API redirecting a logged-in user.
        # However, Day 7 plan implies API-level redirect from get_current_user.
        # For this path, a logged-in user (valid user_id) without seen_welcome cookie: redirect them.
        raise HTTPException(
            status_code=status.HTTP_307_TEMPORARY_REDIRECT,
            detail="Session valid, but welcome not seen. Redirecting.",
            headers={"Location": "/api/v1/onboard/welcome"} # Redirect to the API endpoint for welcome
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