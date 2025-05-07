import sqlite3
import pathlib

DB_FILE = pathlib.Path(__file__).parent.parent / "gibsey.db"

# Establish connection and cursor at module level
con = sqlite3.connect(DB_FILE, check_same_thread=False) # Added check_same_thread=False for FastAPI
cur = con.cursor()

def initialize_db():
    """Creates tables if they don't exist."""
    cur.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE NOT NULL,
        name TEXT,
        pwd_hash TEXT    -- leave NULL for magic-link users
    );
    """)
    cur.execute(""" 
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