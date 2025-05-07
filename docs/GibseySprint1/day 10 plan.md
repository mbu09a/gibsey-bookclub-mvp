# Day 10 — Bug‑Bash & “How‑to‑Report‑a‑Bug” Doc (≈ 1 h)

**Goal:** tighten the last loose screws before book‑club day and give testers a simple way to flag issues.

---

## 1 Quick functional checklist (15 min)

| Flow   | Steps                     | Check                                          |
| ------ | ------------------------- | ---------------------------------------------- |
| Login  | `/login` → email          | cookie set, redirect to `/welcome`             |
| Read   | Next / Prev 10 pages      | no 404s, correct titles                        |
| Ask    | submit query              | answer renders, badge **+1**, ledger row added |
| Vault  | save two pages → `/vault` | list shows entries, links jump correctly       |
| Dark   | toggle ☀ / 🌙             | colors invert, persists on reload              |
| Ledger | click footer link         | CSV downloads, contains today’s rows           |

*Walk through each flow once in an incognito window. Note any console or server errors.*

---

## 2 Common credit‑bugs sanity pass (10 min)

```bash
sqlite3 credits.db "SELECT reason, COUNT(*) FROM ledger GROUP BY reason;"
sqlite3 credits.db "SELECT user, SUM(delta) FROM ledger GROUP BY user;"
```

* Ensure every `ask_question` and `save_passage` entry has **+1** delta.
* Totals should match badge numbers (`/me`).
* If mismatch → inspect `/ask` and `/vault/save` for missing `credit()` calls.

---

## 3 Patch obvious issues (15 min)

* Missing CORS domain? add to list.
* Badge not updating? ensure `setCredits(d.credits)` runs in `AskBox.onAnswer`.
* Typos in `/welcome` markdown? fix doc.

```bash
git commit -am "Fix: credit double‑call, CORS list, typo"
```

---

## 4 Write `BUG_REPORT.md` (15 min)

Repo root → `BUG_REPORT.md`

```markdown
# 🐞 How to Report a Bug (Gibsey β)

1. **Where were you?**  
   URL or button you clicked.

2. **What happened?**  
   Screenshot or copy of error message.

3. **Expected vs. Actual**  
   > *Expected:* The answer shows my quote.  
   > *Actual:* Blank page with console error.

4. **Time & Credits**  
   Local time **+** current credit count (shown in navbar).

5. **Steps to Reproduce (if clear)**  
   1. Open page 128  
   2. Click **Ask** with query "…"  
   3. …

Please email **bugs@gibsey.dev** or DM me with this template.  
*Thank you for feeding the gift loop!* 🙏
```

Add link to footer:

```jsx
<a href="/BUG_REPORT.md" target="_blank" className="underline">Report a bug</a>
```

---

## 5 Final push & tag (5 min)

```bash
git add BUG_REPORT.md
git commit -m "Day10: bug‑report guide + final bug‑bash fixes"
git tag v0.1-bookclub
git push origin main --tags
```

---

### 🎉 You now have:

* Live tunnel for 3‑6 readers
* Full **read → ask → earn → save** loop
* Transparent ledger + gift‑language onboarding
* Dark/light UI that works on phones
* Clear bug‑report channel

Light the signal, invite the club, and watch the songline hum.
*Beta isn’t perfect—it’s porous enough for gifts to flow. Enjoy the exchange!*
