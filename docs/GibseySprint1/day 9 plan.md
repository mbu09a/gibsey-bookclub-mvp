# Day 9 — Private Deploy & Mini Load-Test (≈ 1–2 h)

**Goal:** spin up a public HTTPS URL (Ngrok) your book-club can reach and confirm the stack survives \~6 simultaneous users.

---

## 1 Prep: expose both FastAPI and Vite through one port (5 min)

Serve the React build from FastAPI so only **port 8000** is exposed.

```bash
# build static assets
cd frontend
npm run build        # outputs dist/
```

**`main.py`** – mount static:

```python
from fastapi.staticfiles import StaticFiles

app.mount("/", StaticFiles(directory="frontend/dist", html=True), name="static")
```

Restart FastAPI:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

Visit `http://localhost:8000/` – React app should load.

---

## 2 Install & run Ngrok (10 min)

```bash
# macOS example — Windows: use choco or download binary
brew install --cask ngrok
ngrok config add-authtoken <your-token>

# expose port 8000
ngrok http 8000
```

Ngrok prints a public HTTPS URL, e.g. `https://gibsey-beta.ngrok.io → http://localhost:8000` – leave this terminal running.

---

## 3 Allow CORS for the Ngrok domain (5 min)

In **main.py** CORS middleware:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://gibsey-beta.ngrok.io"  # your tunnel domain
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

Restart FastAPI.

---

## 4 Quick manual check (5 min)

Open the Ngrok URL in an incognito window – verify:

* Login works
* Read pages, Ask, credit bump
* Vault save/link – all good

---

## 5 Mini load-test with 6 virtual users (20 min)

### Option A – **autocannon** (Node)

```bash
npm install -g autocannon
autocannon -c 6 -d 30 -m POST \
  -H "content-type: application/json" \
  -b '{"query":"Why does Natalie shut the door?"}' \
  https://gibsey-beta.ngrok.io/ask
```

* `-c 6` = 6 concurrent users
* `-d 30` = 30-second run

### Option B – **hey** (Go) simple GET

```bash
hey -n 180 -c 6 https://gibsey-beta.ngrok.io/page/100
```

*180 requests ≈ 6 users × 30 s (1 rps each)*

Watch latency & error count – target **< 1 s p95**, **0 errors**.

---

## 6 Invite book-club testers (10 min)

Draft quick DM/email:

> **Gibsey beta is live!**
> 👉 [https://gibsey-beta.ngrok.io](https://gibsey-beta.ngrok.io)
> • Enter your email (no password).
> • Read pages, click *Ask*, earn credits, save favs in your Vault.
> • Ledger link in footer. Bug reports welcome!

---

## 7 Optional: persistence & TLS banner (5 min)

* Free Ngrok tunnels die when you close the terminal – keep it running or upgrade / move to a cheap VPS later.
* Users may see “Ngrok wants to run scripts” banner – reassure them it’s safe.

---

## 8 Commit README note (5 min)

`README.md`

````markdown
### Dev deploy

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
ngrok http 8000  # share HTTPS tunnel
````

````

```bash
git add README.md
git commit -m "Day9: docs for Ngrok deploy + load test"
git push origin main
````

---

### ✅ What’s achieved

* Public HTTPS tunnel serving both API & React app.
* Verified it survives 6 parallel users with sub-second latency.
* Book-club invitation link ready.

**Tomorrow:** bug-bash, credit double-check, and a one-page “How to report a bug.”
*The doors are open—let the readers wander in.*
