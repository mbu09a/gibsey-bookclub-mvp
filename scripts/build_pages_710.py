import re, json, pathlib, textwrap, sys

PROJECT_ROOT = pathlib.Path(__file__).parent.parent
SRC  = PROJECT_ROOT / "cleaned_normalised.txt"
DEST = PROJECT_ROOT / "data" / "pages_710.json"
DEST.parent.mkdir(parents=True, exist_ok=True)

print(f"Reading from: {SRC}")
if not SRC.exists():
    print(f"ERROR: Source file {SRC} not found.")
    sys.exit(1)

raw = SRC.read_text(encoding='utf-8')
# Split by ###Page <digits>###, keep content after the split, skip first empty part if any
# This regex captures the page content following the header.
# Using a lookbehind `(?<=...)` to avoid including the delimiter in the split result, but re.split is tricky with variable length lookbehinds.
# A simpler approach is to split by the full pattern and then filter.

# The original regex `re.split(r"###Page \d+###", raw)[1:]` works well if the first part before Page 1 is junk.
# If there's no text before "###Page 1###", the first element of split will be empty.
chunks = re.split(r"###Page \d+###", raw)

# If the file starts with "###Page 1###", the first chunk from split will be empty.
# Otherwise, it contains text before the first page marker.
if chunks and chunks[0].strip() == "":
    chunks_to_process = chunks[1:]
    print(f"Split into {len(chunks_to_process)} chunks (first was empty, skipped).")
elif chunks:
    # This case implies there was text before the first "###Page <d>###" marker, 
    # and re.split would put that text in chunks[0].
    # If your file format guarantees it starts with ###Page 1###, chunks[0] should be empty.
    # For safety, we assume if chunks[0] is not empty, it might be content before page 1 or a malformed start.
    # The original plan's [1:] assumes the first split part is to be ignored.
    chunks_to_process = chunks[1:] 
    print(f"Split into {len(chunks_to_process)} chunks. First chunk (before first page marker or if no marker at start) was ignored or not page content.")
else:
    print("ERROR: Could not split the source file into page chunks.")
    sys.exit(1)

pages = []
for idx, chunk_text in enumerate(chunks_to_process, 1):
    # Process each chunk
    # Remove leading/trailing whitespace from the chunk itself
    processed_chunk_text = chunk_text.strip()
    
    # Split into lines, strip each line, and keep only non-empty lines
    lines = [l.strip() for l in processed_chunk_text.splitlines() if l.strip()]
    
    if not lines:
        print(f"Warning: Page {idx} (original chunk index {idx-1}) resulted in no content lines after stripping. Skipping.")
        continue
        
    title = textwrap.shorten(lines[0], width=50, placeholder="…")
    # Join lines with a single space, effectively re-flowing paragraphs that might have been split by newlines
    full_text = " ".join(lines) 
    
    pages.append({
        "id": idx,
        "title": title,
        "text": full_text
    })

with DEST.open("w", encoding='utf-8') as f:
    json.dump(pages, f, ensure_ascii=False, indent=2)

print(f"Saved {len(pages)} pages to {DEST}") 