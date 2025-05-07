# Day 4 — Credits Badge & `/me` Endpoint (≈ 1 – 2 h)

**Goal:** readers always see their current credit total in the navbar, and it bumps immediately after each successful **Ask**.

---

## 0 Prereqs (5 min)

You already have:

* `credit(user_id, +1, reason)` in **core/ledger.py**
* `/ask` route that returns `"credits": new_balance`

If a `get_balance()` helper is missing, add:

```python
def get_balance(uid: int) -> int:
    cur.execute("SELECT COALESCE(SUM(delta),0) FROM ledger WHERE user=?", (uid,))
    return cur.fetchone()[0]
```

---

## 1 Backend `/me` route (10 min)

`api/routes/me.py`

```python
from fastapi import APIRouter, Depends
from core.auth import current_user
from core.ledger import get_balance

router = APIRouter()

@router.get("/me")
def me(user = Depends(current_user)):
    return {
        "id": user["id"],
        "email": user["email"],
        "name": user["name"],
        "credits": get_balance(user["id"])
    }
```

Add to **main.py**:

```python
app.include_router(me.router)
```

---

## 2 React `CreditsBadge` component (15 min)

`frontend/CreditsBadge.jsx`

```jsx
import { useState, useEffect } from "react";

export default function CreditsBadge({ credits }) {
  if (credits == null) return null;
  return (
    <span className="px-2 py-1 rounded bg-emerald-600 text-white text-sm">
      💠 {credits}
    </span>
  );
}

export function useCredits() {
  const [cred, setCred] = useState(null);
  useEffect(() => {
    fetch("/me")
      .then((r) => r.json())
      .then((d) => setCred(d.credits));
  }, []);
  return [cred, setCred];
}
```

---

## 3 Integrate badge + live bump (25 min)

*Update **Reader.jsx** — key additions highlighted*

```jsx
import CreditsBadge, { useCredits } from "./CreditsBadge";

export default function Reader() {
  const [pid, setPid] = useState(1);
  const [answer, setAnswer] = useState(null);
  const [credits, setCredits] = useCredits(); // NEW

  const nxt = () => setPid((p) => p + 1);
  const prv = () => setPid((p) => Math.max(1, p - 1));

  return (
    <div>
      <nav className="flex justify-between items-center p-4 bg-gray-100">
        <button onClick={prv}>◀ Prev</button>
        <span>Page {pid}</span>
        <div className="flex gap-3">
          <CreditsBadge credits={credits} />
          <button onClick={nxt}>Next ▶</button>
        </div>
      </nav>

      <Page pid={pid} />

      <AskBox
        onAnswer={(d) => {
          setAnswer(d);
          setCredits(d.credits); // live bump
          window.scrollTo({ top: 0, behavior: "smooth" });
        }}
      />

      <AnswerPane data={answer} setPageId={setPid} />
    </div>
  );
}
```

---

## 4 Smoke test (10 min)

1. Start **uvicorn** (`main:app --reload`) and Vite dev server.
2. **Login** → `/reader`. Badge should fetch and show, e.g., **💠 0**.
3. Ask a question → answer appears; badge bumps to **💠 1**.
4. Reload page → badge still shows **1** (persists via `/me`).

---

## 5 Basic styling tweak (5 min)

Add to `index.css` (or Tailwind layer):

```css
nav button {
  padding: 4px 10px;
  border: 1px solid #ccc;
  border-radius: 4px;
}
nav button:hover {
  background: #eee;
}
```

---

## 6 Commit & push (5 min)

```bash
git add api frontend
git commit -m "Day4: /me endpoint + live credits badge"
git push origin feat/bookclub-credits
```

---

### ✅ Done for Day 4

Visible reciprocity is now real-time.

**Tomorrow:** Vault MVP so readers can save favorite passages.
Every thoughtful question earns its gleaming shard—watch the tally grow!
