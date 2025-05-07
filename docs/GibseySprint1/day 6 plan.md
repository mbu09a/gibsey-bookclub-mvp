# Day 6 — Ledger CSV & Public Link (≈ 1 h)

**Goal:** anyone—reader or outsider—can download the up-to-date credit ledger at `/ledger.csv`, and the file refreshes automatically once per night.

---

## 0 Prereqs (3 min)

`credits.db` already tracks all credit rows:

| user | delta | reason | ts |
| ---- | ----- | ------ | -- |

(If you skipped “credit on save” yesterday, no issue.)

---

## 1 Export helper script (10 min)

`scripts/export_ledger.py`

```python
#!/usr/bin/env python3
import sqlite3, csv, time, pathlib

DB = "credits.db"
OUT = pathlib.Path("public/ledger.csv")
OUT.parent.mkdir(exist_ok=True)

def main():
    with sqlite3.connect(DB) as con, OUT.open("w", newline="") as f:
        cur = con.cursor()
        cur.execute(
            """
            SELECT users.email,
                   ledger.delta,
                   ledger.reason,
                   datetime(ledger.ts,'unixepoch') AS time
            FROM ledger JOIN users ON users.id = ledger.user
            ORDER BY ledger.ts DESC
            """
        )
        csv.writer(f).writerows([["email", "delta", "reason", "time"], *cur.fetchall()])
    print(f"[{time.strftime('%F %T')}] CSV exported → {OUT}")

if __name__ == "__main__":
    main()
```

```bash
chmod +x scripts/export_ledger.py
python scripts/export_ledger.py   # check public/ledger.csv
```

---

## 2 Nightly cron job (10 min)

**Unix / macOS**

```bash
crontab -e
# add line (3 am local time):
0 3 * * * /path/to/project/scripts/export_ledger.py
```

**Windows** — use Task Scheduler with the same command.

---

## 3 On-demand FastAPI route (10 min)

`api/routes/ledger.py`

```python
from fastapi import APIRouter
from fastapi.responses import FileResponse
from pathlib import Path
from scripts.export_ledger import OUT as LEDGER_PATH, main as export_now

router = APIRouter()

@router.get("/ledger.csv")
def ledger_csv():
    if not LEDGER_PATH.exists():
        export_now()  # generate once if cron hasn’t run yet
    return FileResponse(
        LEDGER_PATH,
        media_type="text/csv",
        filename="ledger.csv",
    )
```

Add to **main.py**:

```python
app.include_router(ledger.router)
```

---

## 4 Link in UI footer (10 min)

`frontend/Footer.jsx`

```jsx
export default function Footer() {
  return (
    <footer className="text-center text-sm p-4 text-gray-500">
      <a
        href="/ledger.csv"
        target="_blank"
        rel="noopener"
        className="underline"
      >
        Community ledger (CSV)
      </a>
    </footer>
  );
}
```

Include `<Footer/>` just under the `Reader` root or in your main layout component.

---

## 5 Smoke test (10 min)

1. Run API (`uvicorn main:app --reload`).
2. Visit `http://localhost:8000/ledger.csv` – browser downloads CSV with header row + entries.
3. Trigger a new credit (ask a question).
4. Re-run `python scripts/export_ledger.py`; refresh CSV — new line appears.
5. Confirm cron entry with `crontab -l`.

---

## 6 Commit & push (5 min)

```bash
git add scripts/export_ledger.py api frontend public
git commit -m "Day6: public ledger CSV + nightly export + /ledger.csv route"
git push origin feat/bookclub-ledger
```

---

### ✅ What’s live now

* Transparent ledger file anyone can audit.
* Automatic nightly refresh, plus instant on-demand export.
* Footer link for book-club readers.

Sun goes down, the ledger refreshes—gift economics in plain sight.
