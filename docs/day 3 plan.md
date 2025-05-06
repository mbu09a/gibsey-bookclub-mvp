# Day 3 — Ask UI (≈ 1–2 h)

**Goal:** a reader can type a question, hit **Ask**, see the Literary-Guide answer, and click any cited quote to jump directly to that page in the Reader.

---

## 0 Prereqs (5 min)

Backend `/ask` route should return:

```json
{
  "answer": "Natalie closes the door… {\"page_id\":128,\"loc\":\"p128-3\",\"quote\":\"Natalie…\"}",
  "citations": [128, 130],
  "credits": 6
}
```

If not implemented yet, stub a simple echo route:

```python
@router.post("/ask")
def ask(q: dict, user=Depends(current_user)):
    return {
        "answer": f'Work-in-progress answer to "{q["query"]}"',
        "citations": [],
        "credits": 0,
    }
```

Add CORS if the React dev server runs on **:5173**:

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

---

## 1 `AskBox` component (15 min)

`frontend/AskBox.jsx`

```jsx
import { useState } from "react";

export default function AskBox({ onAnswer }) {
  const [q, setQ] = useState("");
  const [busy, setBusy] = useState(false);

  async function send(e) {
    e.preventDefault();
    if (!q.trim()) return;
    setBusy(true);
    const res = await fetch("/ask", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: q }),
    });
    const data = await res.json();
    setBusy(false);
    setQ("");
    onAnswer(data);
  }

  return (
    <form onSubmit={send} className="flex gap-2 mt-4">
      <input
        className="flex-1 border p-2"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Ask Gibsey…"
        disabled={busy}
      />
      <button
        className="px-3 py-2 bg-black text-white rounded"
        disabled={busy}
      >
        {busy ? "…" : "Ask"}
      </button>
    </form>
  );
}
```

---

## 2 Quote-link parser (20 min)

`frontend/AnswerPane.jsx`

```jsx
function parseAnswer(raw) {
  // Replace embedded JSON quotes with clickable spans
  return raw.replace(
    /\{ *"page_id":(\d+).*?"quote":"([^"]+?)"\}/g,
    (_match, pid, quote) =>
      `<span class="quote" data-pid="${pid}">"${quote}"</span>`
  );
}

export default function AnswerPane({ data, setPageId }) {
  if (!data) return null;
  const html = parseAnswer(data.answer);
  return (
    <div
      className="border-t mt-4 pt-4 prose max-w-2xl mx-auto"
      dangerouslySetInnerHTML={{ __html: html }}
      onClick={(e) => {
        const el = e.target.closest(".quote");
        if (el) setPageId(Number(el.dataset.pid));
      }}
    />
  );
}
```

*Uses `dangerouslySetInnerHTML` for brevity—fine for a trusted backend. If you prefer Markdown parsing: `npm i react-markdown` and adjust accordingly.*

---

## 3 Integrate into Reader (20 min)

*Update `frontend/Reader.jsx` — additions shown in **bold***

```jsx
import { useState, useEffect } from "react";
import Page from "./Page";           // existing component
import **AskBox** from "./AskBox";
import **AnswerPane** from "./AnswerPane";

export default function Reader() {
  const [pid, setPid] = useState(1);
  const [answer, setAnswer] = useState(null);

  const nxt = () => setPid((p) => p + 1);
  const prv = () => setPid((p) => Math.max(1, p - 1));

  return (
    <div>
      <nav className="flex justify-between p-4 bg-gray-100">
        <button onClick={prv} className="px-3 py-1 border rounded">◀ Prev</button>
        <span>Page {pid}</span>
        <button onClick={nxt} className="px-3 py-1 border rounded">Next ▶</button>
      </nav>

      <Page pid={pid} />

      <AskBox onAnswer={(d) => {
        setAnswer(d);
        window.scrollTo({ top: 0, behavior: "smooth" });
      }} />

      <AnswerPane data={answer} setPageId={setPid} />
    </div>
  );
}
```

---

## 4 Manual smoke test (10 min)

1. **Login** → `/reader`.
2. Ask: “Why does Natalie shut the door?”
3. Answer text appears (stub shows placeholder).
4. Click a highlighted quote → Reader jumps to that page.
5. Network tab shows `POST /ask 200` with JSON.

---

## 5 Styling quick pass (5 min)

Add to `index.css` (or Tailwind layer):

```css
.quote {
  cursor: pointer;
  background: #fff7d6;
}
.quote:hover {
  background: #ffe8a8;
}
```

---

## 6 Commit & push (5 min)

```bash
git add frontend api
git commit -m "Day3: Ask UI with clickable citations"
git push origin feat/bookclub-ask-ui
```

---

### ✅ What’s live after Day 3

* Textbox → `/ask` → Literary answer.
* Citations inside answers are click-jump shortcuts into the novel.

**Tomorrow:** wire `/me` and a credits badge so each ask visibly earns a token.
Question asked, gift given—story deepens. Onward!
