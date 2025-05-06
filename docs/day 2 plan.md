# Day 2 — “Serve Pages” (≈ 1 – 2 h)

**Goal:** a logged‑in reader can hit `/reader` in the browser, see page 1 of *The Entrance Way*, and click **Next / Prev** arrows to move through the book.

---

## 0 Prereqs (5 min)

Ensure `pages_100w.json` exists in **data/**:

```json
[
  { "id": 1, "title": "Chapter 1 — Threshold", "text": "Natalie stood before…" },
  { "id": 2, "title": "Chapter 1 — p2",       "text": "The brass knob was…" }
  // …
]
```

---

## 1 Backend route `/page/{id}` (10 min)

`api/routes/pages.py`

```python
from fastapi import APIRouter, Depends, HTTPException
from core.auth import current_user
import json, pathlib

PAGES = {p["id"]: p for p in json.load(open(pathlib.Path("data/pages_100w.json")))}

router = APIRouter()

@router.get("/page/{pid}")
def get_page(pid: int, user=Depends(current_user)):
    page = PAGES.get(pid)
    if not page:
        raise HTTPException(404, "Page not found")
    return {"id": page["id"], "title": page["title"], "text": page["text"]}
```

Add to `main.py`:

```python
app.include_router(pages.router)
```

---

## 2 Reader React component (25 min)

`frontend/Reader.jsx`

```jsx
import { useState, useEffect } from "react";

function Page({ pid }) {
  const [data, setData] = useState(null);
  useEffect(() => {
    fetch(`/page/${pid}`)
      .then((r) => r.json())
      .then(setData);
  }, [pid]);
  if (!data) return <p>Loading…</p>;
  return (
    <article className="prose max-w-2xl mx-auto p-4">
      <h2 className="text-lg font-bold mb-2">{data.title}</h2>
      <p className="whitespace-pre-wrap leading-7">{data.text}</p>
    </article>
  );
}

export default function Reader() {
  const [pid, setPid] = useState(1);
  const nxt = () => setPid((p) => p + 1);
  const prv = () => setPid((p) => Math.max(1, p - 1));
  return (
    <div>
      <nav className="flex justify-between p-4 bg-gray-100">
        <button onClick={prv} className="px-3 py-1 border rounded">
          ◀ Prev
        </button>
        <span>Page {pid}</span>
        <button onClick={nxt} className="px-3 py-1 border rounded">
          Next ▶
        </button>
      </nav>
      <Page pid={pid} />
    </div>
  );
}
```

*If you’re using Vite:* create a route `/reader` that renders `<Reader/>`.

---

## 3 Serve React assets via FastAPI (10 min)

Dev‑time workflow:

```bash
cd frontend
npm run dev   # Vite hot‑reload on :5173
```

Proxy API calls to `localhost:8000` (configure `vite.config.js`).

---

## 4 Manual smoke test (10 min)

```bash
uvicorn main:app --reload
```

1. **Login** via Day 1 (`/login`).
2. Visit `/reader` (`http://localhost:5173/reader` in dev).
3. Page 1 text should render.
4. Click **Next** twice → page 3 appears.
5. **Prev** never goes below page 1.
6. DevTools ➜ *Network* → verify `GET /page/3 200`.

---

## 5 Edge‑case guard (5 min)

Backend:

```python
if pid < 1 or pid > max(PAGES):
    raise HTTPException(404)
```

Frontend: disable **Next** when `pid === max`.

---

## 6 Commit & push (5 min)

```bash
git add data/pages_100w.json api frontend
git commit -m "Day2: page API + React reader with Next/Prev"
git push origin feat/bookclub-reader
```

---

### ✅ What’s done after Day 2

* Authenticated users
* `/page/{id}` JSON API
* React reader that pages through the novel

**Tomorrow:** Ask UI — textbox, `/ask` call, clickable citations.
Page by page, the doorway widens.
