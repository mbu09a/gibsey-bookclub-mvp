# Day 5 — Vault MVP (≈ 1 – 2 h)

**Goal:** a reader can click **Save** while viewing a page, stash it in a personal Vault, and later open `/vault` to see their saved passages.

---

## 0 Prereqs (5 min)

```bash
pip install python-slugify   # for page slugs (optional)
```

---

## 1 Add `vault` table (10 min)

Extend **core/db.py**

```python
cur.execute("""
CREATE TABLE IF NOT EXISTS vault (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    user     INT REFERENCES users(id),
    page_id  INT,
    note     TEXT,
    ts       INT
);
""")
con.commit()
```

---

## 2 Backend routes (20 min)

`api/routes/vault.py`

```python
from fastapi import APIRouter, Depends, HTTPException
from core.auth import current_user
from core.db import con
import time

router = APIRouter()

@router.post("/vault/save")
def save(page_id: int, note: str = "", user = Depends(current_user)):
    cur = con.cursor()
    # prevent duplicates
    cur.execute("SELECT 1 FROM vault WHERE user=? AND page_id=?", (user["id"], page_id))
    if cur.fetchone():
        raise HTTPException(409, "Already saved")
    cur.execute(
        "INSERT INTO vault(user,page_id,note,ts) VALUES(?,?,?,?)",
        (user["id"], page_id, note, int(time.time()))
    )
    con.commit()
    return {"ok": True}

@router.get("/vault")
def list_vault(user = Depends(current_user)):
    cur = con.cursor()
    cur.execute(
        """SELECT v.id, v.page_id, v.note, v.ts, p.title
               FROM vault v JOIN pages p ON p.id = v.page_id
               WHERE v.user = ? ORDER BY v.ts DESC""",
        (user["id"],)
    )
    rows = [dict(zip(["id", "page_id", "note", "ts", "title"], r)) for r in cur.fetchall()]
    return rows
```

Add router to **main.py**:

```python
app.include_router(vault.router)
```

---

## 3 Add “Save passage” button to `Page` component (20 min)

`frontend/Page.jsx` (or inline inside `Reader.jsx`)

```jsx
function Page({ pid }) {
  const [data, setData] = useState(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => setSaved(false), [pid]); // reset when page changes

  useEffect(() => {
    fetch(`/page/${pid}`)
      .then((r) => r.json())
      .then(setData);
  }, [pid]);

  async function save() {
    const res = await fetch(`/vault/save?page_id=${pid}`, { method: "POST" });
    if (res.ok) setSaved(true);
  }

  if (!data) return <p>Loading…</p>;

  return (
    <article className="prose max-w-2xl mx-auto p-4">
      <div className="flex justify-between">
        <h2 className="font-bold">{data.title}</h2>
        <button
          onClick={save}
          disabled={saved}
          className={`text-sm px-2 py-1 rounded ${saved ? "bg-gray-300" : "bg-emerald-600 text-white"}`}
        >
          {saved ? "Saved ✓" : "💾 Save"}
        </button>
      </div>
      <p className="whitespace-pre-wrap leading-7">{data.text}</p>
    </article>
  );
}
```

---

## 4 Vault list page (20 min)

`frontend/Vault.jsx`

```jsx
import { useEffect, useState } from "react";

export default function Vault({ setPageId }) {
  const [rows, setRows] = useState(null);

  useEffect(() => {
    fetch("/vault").then((r) => r.json()).then(setRows);
  }, []);

  if (!rows) return <p className="p-4">Loading…</p>;

  return (
    <div className="max-w-2xl mx-auto p-4">
      <h1 className="text-xl mb-4">My Vault</h1>
      {rows.length === 0 && <p>No passages saved yet.</p>}
      <ul className="space-y-3">
        {rows.map((r) => (
          <li key={r.id} className="border p-3 rounded">
            <button
              onClick={() => setPageId(r.page_id)}
              className="font-semibold text-emerald-700 underline"
            >
              {r.title} (page {r.page_id})
            </button>
            {r.note && <p className="mt-1 italic">{r.note}</p>}
          </li>
        ))}
      </ul>
    </div>
  );
}
```

---

## 5 Add navigation link (5 min)

If you have a simple top‑bar component, append:

```jsx
<Link to="/vault">Vault</Link>
```

Route setup (React Router):

```jsx
<Route path="/vault" element={<Vault setPageId={setPid} />} />
```

---

## 6 Smoke test (10 min)

1. **Login** → `/reader`, click **💾 Save** → button shows “Saved ✓”.
2. Visit `/vault` – entry appears; click link → Reader jumps to that page.
3. Attempt to save the same page again → backend 409, UI still shows *Saved*.
4. Log in with a second email – Vault is empty (per‑user isolation confirmed).

---

## 7 (Option) Earn credit for saves (5 min)

In `save()` route:

```python
from core.ledger import credit
credit(user["id"], +1, "save_passage")
```

The front‑end badge will auto‑bump after a `/me` refresh (or call `/me` after save).

---

## 8 Commit & push (5 min)

```bash
git add api frontend
git commit -m "Day5: personal Vault (save & list passages)"
git push origin feat/bookclub-vault
```

---

### ✅ Vault MVP complete

Readers can now curate and revisit their favorite passages—fuel for deeper discussion.

**Tomorrow:** automate ledger transparency with a CSV export.
A safe place for every treasured line—Gibsey remembers with you.
