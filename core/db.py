import sqlite3
import pathlib

DB_FILE = pathlib.Path(__file__).parent.parent / "gibsey.db"

def main():
    con = sqlite3.connect(DB_FILE)
    cur = con.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE NOT NULL,
        name TEXT,
        pwd_hash TEXT    -- leave NULL for magic-link users
    );
    """)
    con.commit()
    con.close()
    print(f"Database {DB_FILE} initialized and users table created.")

if __name__ == "__main__":
    main() 