# Day 7 — Onboarding Page (≈ 1 h)

**Goal:** every new reader lands on a friendly “Welcome to Gibsey Beta” screen that

1. explains the gift‑loop rules, 2) shows quick‑start tips, and 3) lets them click **Enter** to jump into `/reader`.

---

## 1 Create the markdown file (5 min)

`docs/onboarding.md`

```markdown
# Welcome to **Gibsey β**

Gibsey is a *living edition* of **_The Entrance Way_**.

### How the gift loop works

1. **Read** — browse 100‑word pages.  
2. **Ask** — pose any question; Gibsey responds with cited quotes.  
3. **Earn** — each helpful question or annotation = **+1 credit**.  
4. **Give back** — spend credits on deeper analyses; save passages to your Vault.  
5. **Share** — the ledger is public; value flows sideways, not up.

> “Receive curiosity as a gift; offer insight in return.”

Enjoy exploring, and thank you for keeping the loop alive!
```

*(Feel free to embellish later—keep it minimal for now.)*

---

## 2 Serve markdown as HTML (10 min)

`api/routes/onboard.py`

```python
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
import markdown, pathlib

router = APIRouter()

MD_PATH = pathlib.Path("docs/onboarding.md")

@router.get("/welcome", response_class=HTMLResponse)
def welcome(request: Request):
    html_body = markdown.markdown(MD_PATH.read_text())
    return f"""
    <html><head>
      <title>Welcome to Gibsey β</title>
      <link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/tailwindcss@3/dist/tailwind.min.css\">
    </head><body class=\"prose mx-auto p-8\">{html_body}
      <form method=\"post\" action=\"/welcome/enter\">
        <button class=\"mt-8 px-4 py-2 bg-emerald-600 text-white rounded\">Enter Gibsey →</button>
      </form>
    </body></html>"""
```

Register in **main.py**:

```python
app.include_router(onboard.router)
```

---

## 3 Redirect first‑time users to `/welcome` (10 min)

Update `core/auth.py` dependency:

```python
from fastapi import Request, HTTPException, status

def current_user(..., request: Request):
    ...
    if not request.cookies.get("seen_welcome"):
        raise HTTPException(status.HTTP_307_TEMPORARY_REDIRECT,
                            headers={"Location": "/welcome"})
    return user
```

In `api/routes/onboard.py` add enter endpoint:

```python
from fastapi.responses import RedirectResponse

@router.post("/welcome/enter")
def enter():
    resp = RedirectResponse("/reader", status_code=303)
    resp.set_cookie("seen_welcome", "1", max_age=31536000)  # 1 year
    return resp
```

---

## 4 Link from login footer (5 min)

`Login.jsx`

```jsx
<footer className="text-center text-xs text-gray-400 mt-4">
  <a href="/welcome" className="underline">What is this?</a>
</footer>
```

---

## 5 Smoke test (10 min)

1. **Log out / clear cookies** → visit `localhost:8000/login`.
2. Sign in → should be bounced to `/welcome`.
3. Read page → click **Enter** → lands in `/reader`, cookie `seen_welcome=1`.
4. Refresh — stays in `/reader` (no loop).
5. Delete the cookie → reload → redirected again (works).

---

## 6 Commit & push (5 min)

```bash
git add docs api frontend
git commit -m "Day7: onboarding markdown + welcome flow"
git push origin feat/bookclub-onboarding
```

---

### ✅ Onboarding done!

Now every club member starts with clarity and the gift‑loop mindset.

**Tomorrow:** polish CSS and add a dark‑mode toggle for comfy night reading.
*A clear threshold invites the best journeys—step through, gifts in hand.*
