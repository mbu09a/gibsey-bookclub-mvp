#!/usr/bin/env python3
import sqlite3
import csv
import time
import pathlib

# Define project root assuming this script is in /scripts/
PROJECT_ROOT = pathlib.Path(__file__).parent.parent
DB_PATH = PROJECT_ROOT / "gibsey.db" # Path to the SQLite DB file
OUTPUT_DIR = PROJECT_ROOT / "public"
OUTPUT_CSV_FILE = OUTPUT_DIR / "ledger.csv"

def main():
    """Connects to the SQLite database, queries the ledger, and writes it to a CSV file."""
    
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True) # Ensure the /public directory exists

    # Use a context manager for the database connection to ensure it's closed
    try:
        with sqlite3.connect(DB_PATH) as con:
            cur = con.cursor()
            cur.execute(
                """SELECT 
                       u.email, 
                       l.delta, 
                       l.reason, 
                       datetime(l.ts, 'unixepoch', 'localtime') AS transaction_time
                   FROM ledger l
                   JOIN users u ON u.id = l.user_id
                   ORDER BY l.ts DESC"""
            )
            rows = cur.fetchall()
            headers = [description[0] for description in cur.description]

            with OUTPUT_CSV_FILE.open("w", newline="", encoding="utf-8") as f:
                csv_writer = csv.writer(f)
                csv_writer.writerow(headers)
                csv_writer.writerows(rows)
            
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Ledger CSV exported successfully to {OUTPUT_CSV_FILE}")
            print(f"Exported {len(rows)} transaction(s).")

    except sqlite3.Error as e:
        print(f"SQLite error occurred: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    main() 