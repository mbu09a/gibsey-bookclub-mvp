import sqlite3
import pathlib
from typing import Generator # For type hinting the generator

DB_FILE = pathlib.Path(__file__).parent.parent / "gibsey.db"

# No global connection `con` here anymore. 
# Each request will get its own connection via the get_db dependency.

def get_db() -> Generator[sqlite3.Connection, None, None]:
    """
    FastAPI dependency that provides a SQLite database connection.
    Ensures the connection is closed after the request.
    """
    db = None
    try:
        db = sqlite3.connect(DB_FILE, check_same_thread=False) # check_same_thread still useful if threads are used within a request
        yield db
    finally:
        if db:
            db.close()

def initialize_db():
    """Creates tables if they don't exist. Called once on app startup ideally."""
    # This function will now use the get_db pattern for its one-time setup,
    # or be called by main.py using a connection obtained there.
    # For simplicity of ensuring tables exist when any module might be first imported,
    # we can make a temporary direct connection here for initialization.
    # This is less ideal than explicit startup event in main.py, but works for MVP.
    
    temp_con = None
    try:
        temp_con = sqlite3.connect(DB_FILE, check_same_thread=False)
        local_cur = temp_con.cursor()
        try:
            local_cur.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT UNIQUE NOT NULL,
                name TEXT,
                pwd_hash TEXT
            );
            """)
            local_cur.execute(""" 
            CREATE TABLE IF NOT EXISTS ledger (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id),
                delta INTEGER NOT NULL,
                reason TEXT,
                ts INTEGER NOT NULL
            );
            """)
            local_cur.execute(""" 
            CREATE TABLE IF NOT EXISTS vault (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id),
                page_id INTEGER NOT NULL,
                note TEXT,
                ts INTEGER NOT NULL,
                UNIQUE(user_id, page_id)
            );
            """)
            temp_con.commit()
            print(f"Database {DB_FILE} checked by initialize_db(), tables ensured (users, ledger, vault).")
        finally:
            local_cur.close()
    except Exception as e:
        print(f"Error during initialize_db: {e}")
        # If init fails, the app probably shouldn't start, but we let it try.
    finally:
        if temp_con:
            temp_con.close()

# Call initialize_db when this module is first imported.
# This ensures tables are ready before other modules try to use them via get_db.
# In a more complex app, this would be better handled in a FastAPI startup event.
_db_initialized = False
if not _db_initialized:
    initialize_db()
    _db_initialized = True

# Note: The global `con` and `cur` are removed. 
# All DB access should now go through a connection provided by `Depends(get_db)`.

# Note on SQLite and FastAPI:
# While a single shared connection `con` with `check_same_thread=False`