# scripts/build_pages.py
import json, re, pathlib, textwrap

SRC  = pathlib.Path(__file__).parent.parent / "cleaned_normalised.txt"
DEST = pathlib.Path(__file__).parent.parent / "data" / "pages_100w.json"
DEST.parent.mkdir(parents=True, exist_ok=True)

TARGET, LOWER, UPPER = 100, 80, 120 # Target words, lower bound, upper bound

# Regex to split sentences, ensuring it handles various punctuation and spaces correctly.
# It splits after a period, exclamation mark, or question mark, followed by whitespace.
sentences = re.split(r'(?<=[.!?])\s+', SRC.read_text(encoding='utf-8').strip())

pages, buf = [], []

def flush(buffer):
    if not buffer: return
    # Calculate word count for the current buffer
    current_text = " ".join(buffer)
    words_in_buffer = len(current_text.split())
    
    # Generate a title from the first sentence, shortened to 50 chars
    # Using a slice of the text for shorten, as textwrap.shorten works on strings.
    title_source = buffer[0]
    title = textwrap.shorten(title_source, width=50, placeholder="…")
    
    pages.append({"id": len(pages) + 1, "title": title, "text": current_text})

for sent in sentences:
    buf.append(sent)
    # Calculate current word count of the buffer
    current_buffer_text = " ".join(buf)
    wc = len(current_buffer_text.split())
    
    # Check if buffer meets word count criteria to be flushed
    # It flushes if word count is over LOWER and (either over TARGET or over UPPER if it already passed LOWER)
    # This logic aims to keep pages from being too short, while trying to hit TARGET, and not exceeding UPPER too much.
    if wc >= LOWER:
        if wc >= TARGET or len(buf) > 1: # Try to make pages if near target, or if multiple sentences and over lower bound
            flush(buf)
            buf = []

flush(buf) # Flush any remaining sentences in the buffer

with DEST.open("w", encoding='utf-8') as f:
    json.dump(pages, f, ensure_ascii=False, indent=2)

print(f"Wrote {len(pages)} pages → {DEST}") 