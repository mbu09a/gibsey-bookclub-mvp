# Day 1 — Auth Stub (≈ 90 min)

**Goal:** let a book-club reader land on `/login`, enter an email, and receive a session cookie so every subsequent request carries `user_id`.

## 0. Prereqs (revised - budget extra 15-20 min for first-time setup)

### A. Environment Setup (First time only)

It's crucial to set up a proper development environment. This includes version control for your project files and a virtual environment for Python dependencies.

1.  **Initialize Git Repository (if not already done)**:
    If you haven't, initialize a Git repository in your project root, make an initial commit, and connect it to a remote repository (e.g., on GitHub).

2.  **Create `.gitignore**:**
    Create a `.gitignore` file in the project root to prevent committing unnecessary files (like the virtual environment directory, Python cache, OS-specific files).
    Example `\.gitignore` content:
    ```gitignore
    # Python virtual environment
    .venv/
    venv/
    */.venv/
    */venv/

    # Python cache files
    __pycache__/
    *.pyc
    *.pyo
    *.pyd

    # Editor/IDE specific
    .vscode/
    .idea/

    # OS-specific
    .DS_Store
    Thumbs.db
    ```
    Commit this file: `git add .gitignore && git commit -m "Add .gitignore"`

3.  **Create and Activate Python Virtual Environment**:
    Using a virtual environment is highly recommended to manage project dependencies and avoid conflicts with system-wide Python packages.
    ```bash
    # Ensure you are in the project root directory
    python3 -m venv .venv  # Creates a virtual environment named '.venv'
    source .venv/bin/activate # Activates the environment (for bash/zsh on macOS/Linux)
    # For Windows: .venv\Scripts\activate
    ```
    Your terminal prompt should now typically show `(.venv)` at the beginning, indicating the virtual environment is active.

4.  **(Optional but Recommended) Configure Shell PATH for User-Installed Python Scripts**:
    To make Python scripts installed via `pip install --user` (outside a venv) generally accessible (e.g., `uvicorn`, `pip` itself if installed this way), add the user script directory to your shell's PATH. For Zsh on macOS (using `/Users/ghostradongus` as an example home directory):
    *   Edit `~/.zshrc` (e.g., `nano ~/.zshrc`).
    *   Add the line: `export PATH="$HOME/Library/Python/3.9/bin:$PATH"` (adjust Python version if needed).
    *   Save the file and run `source ~/.zshrc` in your terminal for the change to take effect in the current session.
    *   *Note: When the virtual environment (`.venv`) is active, its script directory takes precedence, which is the desired behavior for project-specific tools.*

### B. Install Python Dependencies

Once your virtual environment is active (you see `(.venv)` in your prompt), install the required Python packages.

First, create/update `requirements.txt` in your project root with the following content:
```txt
fastapi[all]==0.115.12 # Or your desired/latest version
itsdangerous==2.2.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.20
```

Then, install these dependencies:
```bash
# Ensure pip is up-to-date within the venv (good practice)
python -m pip install --upgrade pip

# Install project dependencies from requirements.txt
pip install -r requirements.txt
```

*(The original Day 1 plan listed individual pip install commands. Using `requirements.txt` is generally preferred for managing dependencies consistently.)*

## 1. Create users table (10 min)

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

## 2. Session signer (5 min)

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

## 3. `/login` API route (20 min)

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

*No password; later swap for magic-link mailer.*
Add router to `main.py`.

## 4. Auth dependency (10 min)

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

## 5. Minimal login HTML (15 min)

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

*Assumes Vite/React setup; route `/reader` will come Day 2.*

## 6. Smoke test (10 min)

```bash
uvicorn main:app --reload
```

* Visit `http://localhost:8000/login` (serve static via FastAPI or dev server).
* Submit email → check browser **DevTools › Cookies**: `gibsey_sid`.
* `sqlite3 gibsey.db "SELECT * FROM users;"` → one row.
* Hit a protected endpoint without cookie → **401**.

## 7. Commit (5 min)

```bash
git add .
git commit -m "Day1: basic email login + session cookie"
git push origin feat/bookclub-auth
```

---

You now have per-user identity.
Tomorrow we'll serve pages and wire the React reader.
*Brick laid—rest up, next brick awaits.*
