import sqlite3
import pathlib

DB_FILE = pathlib.Path(__file__).parent.parent / "gibsey.db"

# Establish connection at module level
# check_same_thread=False is important for FastAPI with SQLite as FastAPI can
# use multiple threads to handle requests, and SQLite connections by default
# are not thread-safe unless this flag is set.
con = sqlite3.connect(DB_FILE, check_same_thread=False)

# No global cursor here anymore: cur = con.cursor()

def initialize_db():
    """Creates tables if they don't exist, using a local cursor."""
    local_cur = con.cursor() # Use a local cursor for setup operations
    try:
        local_cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            name TEXT,
            pwd_hash TEXT    -- leave NULL for magic-link users
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
        # Future: Add an index on ledger (user_id, ts) for faster balance lookups
        # cur.execute("CREATE INDEX IF NOT EXISTS idx_ledger_user_ts ON ledger (user_id, ts DESC);")
        con.commit()
        print(f"Database {DB_FILE} checked, tables ensured (users, ledger).")
    finally:
        local_cur.close() # Ensure local cursor is closed

# Ensure DB is initialized when module is first imported by the app
# The script can also be run directly to initialize
if __name__ == "__main__":
    initialize_db()
    con.close() # Close connection if run as script
else:
    # If imported, ensure the table exists. 
    # FastAPI might run this in multiple workers, so table creation should be idempotent.
    initialize_db()

# Note: For a production app with multiple workers or threads, 
# managing SQLite connections can be tricky. 
# A connection pool or a more robust setup might be needed.
# For this MVP, a single shared connection (with check_same_thread=False) is a simplification. 

# Note on SQLite and FastAPI:
# While a single shared connection `con` with `check_same_thread=False` can work
# for simple applications, cursors should generally be created per operation or 
# per request to avoid issues like "Recursive use of cursors not allowed".
# Each function using the DB will now get its own cursor from `con`.
# For more complex apps, connection pooling or a request-scoped DB session via
# FastAPI dependencies would be a more robust pattern. 