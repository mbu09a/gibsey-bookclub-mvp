import sqlite3 # For type hinting Connection
from fastapi import APIRouter, Form, Response, Depends

from core.db import get_db # Import get_db dependency
from core.session import make_cookie, COOKIE_MAX_AGE_SECONDS

router = APIRouter()

@router.post("/login")
def login(
    email: str = Form(...), 
    name: str = Form("Reader"), 
    resp: Response = Response(),
    db: sqlite3.Connection = Depends(get_db) # Inject DB connection
):
    """Handles user login. Creates a user if one doesn't exist, then sets a session cookie."""
    db_cur = None
    try:
        db_cur = db.cursor()
        db_cur.execute("INSERT OR IGNORE INTO users(email, name) VALUES(?, ?)", (email, name))
        db_cur.execute("SELECT id FROM users WHERE email=?", (email,))
        user_row = db_cur.fetchone()
        db.commit() # Commit on the connection

        if user_row:
            user_id = user_row[0]
            session_cookie_value = make_cookie(user_id)
            resp.set_cookie(
                key="gibsey_sid", 
                value=session_cookie_value, 
                httponly=True, 
                max_age=COOKIE_MAX_AGE_SECONDS,
                samesite="lax" # Good practice for security
            )
            return {"ok": True, "user_id": user_id, "message": "Login successful"}
        else:
            # This case should ideally not be reached if INSERT OR IGNORE and SELECT work as expected
            return {"ok": False, "message": "Failed to retrieve user after insert/ignore"}

    except Exception as e:
        # Consider db.rollback() here if a multi-statement transaction failed
        print(f"Error during login for email {email}: {e}")
        # For an MVP, returning a generic error is okay
        # In production, you'd want more specific error handling and logging
        return {"ok": False, "message": f"An error occurred: {str(e)}"}
    finally:
        if db_cur: # Ensure cursor exists before trying to close
            db_cur.close() # Close the cursor in a finally block 