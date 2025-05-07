import time
from typing import Tuple, Optional, List, Dict, Any

from core.db import con, cur # Import shared connection and cursor

def credit(user_id: int, delta: int, reason: str) -> bool:
    """
    Records a credit transaction in the ledger for a given user.
    Returns True on success, False on failure.
    """
    current_timestamp = int(time.time())
    try:
        cur.execute(
            "INSERT INTO ledger (user_id, delta, reason, ts) VALUES (?, ?, ?, ?)",
            (user_id, delta, reason, current_timestamp)
        )
        con.commit()
        print(f"Ledger entry: User {user_id}, Delta {delta}, Reason '{reason}', TS {current_timestamp}")
        return True
    except Exception as e:
        print(f"Error adding credit to ledger for user {user_id}: {e}")
        # con.rollback() # Consider if an explicit rollback is needed on error, though autocommit might handle simple cases
        return False

def get_balance(user_id: int) -> int:
    """
    Calculates the current credit balance for a given user.
    """
    try:
        cur.execute("SELECT COALESCE(SUM(delta), 0) FROM ledger WHERE user_id = ?", (user_id,))
        result = cur.fetchone()
        return result[0] if result else 0
    except Exception as e:
        print(f"Error fetching balance for user {user_id}: {e}")
        return 0 # Default to 0 on error

# Example of fetching full ledger history for a user (not directly used by /me, but useful for /ledger.csv later)
def get_ledger_entries_for_user(user_id: int) -> List[Dict[str, Any]]:
    """Fetches all ledger entries for a specific user, ordered by time."""
    try:
        cur.execute(
            "SELECT id, delta, reason, ts FROM ledger WHERE user_id = ? ORDER BY ts DESC", 
            (user_id,)
        )
        rows = cur.fetchall()
        # Convert rows to list of dicts
        entries = [{'id': r[0], 'delta': r[1], 'reason': r[2], 'timestamp': r[3]} for r in rows]
        return entries
    except Exception as e:
        print(f"Error fetching ledger entries for user {user_id}: {e}")
        return [] 