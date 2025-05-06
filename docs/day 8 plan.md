# Day 8 — Browser Polish & Dark-Mode Toggle (≈ 1 – 2 h)

**Goal:** your UI already works; now we’ll make it look decent on desktop *and* phones and add a one-click dark theme.

---

## 0 Choose a styling path (2 min)

We’ll use **Tailwind via CDN**—fastest for a prototype.
*(If you’re already bundling Tailwind in Vite, skip the CDN step and just add the classes below.)*

---

## 1 Inject Tailwind CDN (5 min)

Open **`index.html`** (or your main React root):

```html
<head>
  …
  <script src="https://cdn.tailwindcss.com?plugins=typography"></script>
  <script>
    // enable class-based dark mode
    tailwind.config = { darkMode: 'class' };
  </script>
</head>
```

Remove any old inline CSS you no longer need.

---

## 2 Global layout tweaks (15 min)

**`index.css`** (or a `<style>` block):

```css
html,body {
  @apply min-h-screen bg-gray-50 dark:bg-gray-900 text-gray-900 dark:text-gray-100;
}
nav { @apply bg-gray-100 dark:bg-gray-800; }
button { @apply transition; }
```

**Reader page container**
Wrap your main `<div>` in `className="max-w-3xl mx-auto"` to center it on large screens.

**Prose typography**
In `<Page/>` swap `className="prose"` with:

```jsx
className="prose dark:prose-invert"
```

—Tailwind’s typography plugin will invert colors automatically.

---

## 3 Dark-mode toggle component (20 min)

`frontend/DarkToggle.jsx`

```jsx
import { useEffect, useState } from "react";

export default function DarkToggle() {
  const [dark, setDark] = useState(
    localStorage.getItem("theme") === "dark" ||
    window.matchMedia("(prefers-color-scheme: dark)").matches
  );

  useEffect(() => {
    document.documentElement.classList.toggle("dark", dark);
    localStorage.setItem("theme", dark ? "dark" : "light");
  }, [dark]);

  return (
    <button
      onClick={() => setDark(!dark)}
      className="px-2 py-1 border rounded text-sm"
      aria-label="Toggle dark mode"
      title="Toggle dark mode"
    >
      {dark ? "🌙" : "☀️"}
    </button>
  );
}
```

Place it in the top-right corner of the navbar:

```jsx
<nav className="flex justify-between items-center …">
  …existing buttons…
  <div className="flex gap-2">
    <CreditsBadge credits={credits} />
    <DarkToggle />
  </div>
</nav>
```

---

## 4 Mobile responsiveness (15 min)

* **Flex-wrap nav:**

  ```jsx
  className="flex flex-wrap items-center justify-between p-4 space-y-2 sm:space-y-0"
  ```

  so buttons wrap on narrow screens.

* **Text scaling:** add `text-base sm:text-lg` to headings so they shrink on phones.

* **AskBox layout:**

  ```jsx
  className="flex flex-col sm:flex-row gap-2"
  ```

  and set `input` class to `flex-1` so it grows.

---

## 5 Manual device test (10 min)

1. Start Vite dev server: `npm run dev`.
2. Open Chrome DevTools ➜ *Device toolbar* ➜ iPhone SE & iPad.
3. Toggle dark mode; ensure background/text invert correctly.
4. Rotate phone: nav should wrap nicely.

---

## 6 Accessibility quick pass (5 min)

Add **aria-labels** to Prev/Next and DarkToggle buttons:

```jsx
<button aria-label="Previous page">◀ Prev</button>
<button aria-label="Next page">Next ▶</button>
```

---

## 7 Commit & push (5 min)

```bash
git add frontend index.css index.html
git commit -m "Day8: responsive layout + Tailwind dark mode toggle"
git push origin feat/bookclub-styles
```

---

### ✅ What’s done

* Clean, centered layout on desktop
* Mobile-friendly flex + font sizing
* Instant dark/light switch stored in `localStorage`

**Tomorrow:** private deploy via Ngrok and a lightweight load test so your book-club friends can jump in.
Night or day, the doorway now glows in any light.
