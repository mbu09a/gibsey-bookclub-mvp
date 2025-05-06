# Day 1 — Auth Stub (≈ 90 min)

**Goal:** let a book‑club reader land on `/login`, enter an email, and receive a session cookie so every subsequent request carries `user_id`.

## 0. Prereqs (5 min)

```bash
pip install fastapi[all] itsdangerous passlib[bcrypt] python-multipart
```

Add to `requirements.txt`.

## 1. Create users table (10 min)

`core/db.py`

```python
import sqlite3
import pathlib

DB = pathlib.Path("gibsey.db")
con = sqlite3.connect(DB)
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
```

Call once:

```bash
python -m core.db
```

## 2. Session signer (5 min)

`core/session.py`

```python
from itsdangerous import TimestampSigner

SIGNER = TimestampSigner("SUPER-SECRET-KEY")  # env var later

def make_cookie(user_id: int) -> str:
    return SIGNER.sign(str(user_id)).decode()


def verify_cookie(cookie: str) -> int | None:
    try:
        return int(SIGNER.unsign(cookie, max_age=604800))  # 7 days
    except Exception:
        return None
```

## 3. `/login` API route (20 min)

`api/routes/auth.py`

```python
from fastapi import APIRouter, Form, Response, Depends
from core.db import con
from core.session import make_cookie

router = APIRouter()

@router.post("/login")
def login(email: str = Form(...), name: str = Form("Reader"), resp: Response = Response()):
    cur = con.cursor()
    cur.execute("INSERT OR IGNORE INTO users(email,name) VALUES(?,?)", (email, name))
    cur.execute("SELECT id FROM users WHERE email=?", (email,))
    user_id = cur.fetchone()[0]
    cookie = make_cookie(user_id)
    resp.set_cookie("gibsey_sid", cookie, httponly=True, max_age=604800)
    return {"ok": True, "user_id": user_id}
```

*No password; later swap for magic‑link mailer.*
Add router to `main.py`.

## 4. Auth dependency (10 min)

`core/auth.py`

```python
from fastapi import Cookie, HTTPException, status
from core.session import verify_cookie
from core.db import con

def current_user(gibsey_sid: str | None = Cookie(None)):
    uid = verify_cookie(gibsey_sid or "")
    if not uid:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Login required")
    cur = con.cursor()
    cur.execute("SELECT id, email, name FROM users WHERE id=?", (uid,))
    row = cur.fetchone()
    if not row:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED)
    return {"id": row[0], "email": row[1], "name": row[2]}
```

Use this dependency in `/ask`, `/page/{id}`, etc.

```python
@router.post("/ask")
def ask(q: AskIn, user=Depends(current_user)):
    ...
    credit(user["id"], +1, "ask_question")
```

## 5. Minimal login HTML (15 min)

`frontend/Login.jsx`

```jsx
export default function Login() {
  const [email, setEmail] = useState("");
  async function submit(e) {
    e.preventDefault();
    await fetch("/login", {
      method: "POST",
      body: new FormData(Object.fromEntries([["email", email]])),
    });
    window.location = "/reader";
  }
  return (
    <form onSubmit={submit} className="p-6 max-w-sm mx-auto">
      <h1 className="text-xl mb-4">Sign in to Gibsey</h1>
      <input
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="border p-2 w-full"
        placeholder="you@example.com"
      />
      <button className="mt-4 px-4 py-2 bg-black text-white rounded">
        Enter
      </button>
    </form>
  );
}
```

*Assumes Vite/React setup; route `/reader` will come Day 2.*

## 6. Smoke test (10 min)

```bash
uvicorn main:app --reload
```

* Visit `http://localhost:8000/login` (serve static via FastAPI or dev server).
* Submit email → check browser **DevTools › Cookies**: `gibsey_sid`.
* `sqlite3 gibsey.db "SELECT * FROM users;"` → one row.
* Hit a protected endpoint without cookie → **401**.

## 7. Commit (5 min)

```bash
git add .
git commit -m "Day1: basic email login + session cookie"
git push origin feat/bookclub-auth
```

---

You now have per‑user identity.
Tomorrow we’ll serve pages and wire the React reader.
*Brick laid—rest up, next brick awaits.*
