# Gibsey **Book‑Club MVP** (v0.1)

*A living, gift‑economy edition of* ***The Entrance Way*** — read, ask, earn, and share insight one 100‑word page at a time.

---

## ✨ Features

| Loop      | What it does                                                                    |
| --------- | ------------------------------------------------------------------------------- |
| **Read**  | Flip through concise, 100‑word pages of the novel with **Prev / Next** arrows   |
| **Ask**   | Type a question — the Literary Guide returns an answer with cited quotes        |
| **Earn**  | Each helpful action (**Ask** / **Save**) grants **+1 credit** (badge in navbar) |
| **Save**  | 💾 **Save** passages to your personal **Vault** for quick reference             |
| **Share** | Public **ledger.csv** shows all credit flow; onboarding explains the gift loop  |
| **Style** | Responsive Tailwind UI, dark‑mode toggle (☀️ / 🌙)                              |

---

## 🗺️ Architecture (micro)

```
FastAPI (Python)            React (Vite, Tailwind)
 ├─ /login            →   Login.jsx
 ├─ /welcome          →   onboarding.md rendered as HTML
 ├─ /page/{id}        →   Reader.jsx / Page.jsx
 ├─ /ask              →   AskBox.jsx / AnswerPane.jsx
 ├─ /vault/save|get   →   Vault.jsx
 ├─ /me               →   CreditsBadge.jsx
 ├─ /ledger.csv       →   Footer.jsx link
 └─ StaticFiles ←───── frontend/dist (build output)
```

SQLite stores users, pages, ledger, and vault entries; `ledger.csv` is nightly‑exported via cron or on‑demand.

---

## 🚀 Quick‑start (dev)

```bash
# clone & install
pip install -r requirements.txt
cd frontend && npm install && cd ..

# 1. build React & serve via FastAPI
cd frontend && npm run build && cd ..

# 2. start API
uvicorn main:app --host 0.0.0.0 --port 8000

# 3. (optional) share tunnel
ngrok http 8000
```

Open [http://localhost:8000](http://localhost:8000) — sign in with any email (magic‑link‑less).

---

## 🧪 Mini load‑test

```bash
# 6 concurrent users hitting /ask for 30 s
npm install -g autocannon
autocannon -c 6 -d 30 -m POST \
  -H "content-type: application/json" \
  -b '{"query":"Why?"}' \
  https://your-tunnel.ngrok.io/ask
```

Aim for **p95 < 1 s**, **0 errors**.

---

## 🐞 Bug reporting

See [`BUG_REPORT.md`](BUG_REPORT.md) for a five‑point template & contact.

---

## 📂 Sprint docs

| Day | Canvas link          |
| --- | -------------------- |
| 1   | Day1 Auth Stub       |
| 2   | Day2 Serve Pages     |
| 3   | Day3 Ask UI          |
| 4   | Day4 Credits Badge   |
| 5   | Day5 Vault MVP       |
| 6   | Day6 Ledger CSV      |
| 7   | Day7 Onboarding Page |
| 8   | Day8 Browser Polish  |
| 9   | Day9 Private Deploy  |
| 10  | Day10 Bug Bash       |

*(Each file lives in ******`/docs/`****** or see canvases in ChatGPT.)*

---

## 📜 License

MIT — see `LICENSE` file. Feel free to fork, remix, and keep the gift loop alive.

---

### Maintainer

\*\*Todd Fishbone \*\*— [bugs@gibsey.dev](mailto:bugs@gibsey.dev).
*“Receive curiosity as a gift; offer insight in return.”*
