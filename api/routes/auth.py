from fastapi import APIRouter, Form, Response
# We will need Depends for current_user later, but not for login itself

from core.db import con # Only import the connection
from core.session import make_cookie, COOKIE_MAX_AGE_SECONDS

router = APIRouter()

@router.post("/login")
def login(email: str = Form(...), name: str = Form("Reader"), resp: Response = Response()):
    """Handles user login. Creates a user if one doesn't exist, then sets a session cookie."""
    db_cur = None
    try:
        db_cur = con.cursor()
        # Insert new user or ignore if email already exists
        db_cur.execute("INSERT OR IGNORE INTO users(email, name) VALUES(?, ?)", (email, name))
        # No need to commit INSERT OR IGNORE immediately if the subsequent SELECT is on the same user
        # and we commit after all operations for this request succeed.
        
        # Retrieve the user ID (works for both new and existing users)
        db_cur.execute("SELECT id FROM users WHERE email=?", (email,))
        user_row = db_cur.fetchone()
        con.commit() # Commit after all reads/writes for this transaction are staged

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
        # Consider con.rollback() here if a multi-statement transaction failed
        print(f"Error during login for email {email}: {e}")
        # For an MVP, returning a generic error is okay
        # In production, you'd want more specific error handling and logging
        return {"ok": False, "message": f"An error occurred: {str(e)}"}
    finally:
        if db_cur:
            db_cur.close() 