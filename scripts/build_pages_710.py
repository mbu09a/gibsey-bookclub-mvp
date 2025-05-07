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
    # This case implies the first chunk might be content before any page marker,
    # or the file doesn't start with a page marker. Assuming we want to ignore it.
    chunks_to_process = chunks[1:] if len(chunks) > 1 else [] 
    print(f"Split into {len(chunks_to_process)} chunks. First chunk (before first page marker or if no marker at start) was ignored or not page content.")
else:
    print("ERROR: Could not split the source file into page chunks.")
    sys.exit(1)

if not chunks_to_process:
    print("ERROR: No page content found after splitting by page markers.")
    sys.exit(1)

print(f"Processing {len(chunks_to_process)} text chunks for pages.")

pages = []
CHAPTER_TITLE_PATTERN = re.compile(r"^\*\*(.+?)\*\*$") # Matches lines like **Title Here**

for idx, chunk_text in enumerate(chunks_to_process, 1):
    processed_chunk_text = chunk_text.strip()
    lines = [l.strip() for l in processed_chunk_text.splitlines() if l.strip()]
    
    if not lines:
        print(f"Warning: Page {idx} (original chunk index {idx-1}) is empty after stripping. Skipping.")
        continue
        
    page_title = f"Page {idx}" # Default title
    page_text_lines = lines
    
    # Check if the first line is a chapter/section title
    title_match = CHAPTER_TITLE_PATTERN.match(lines[0])
    if title_match:
        extracted_title = title_match.group(1).strip()
        if len(extracted_title) > 3: # Arbitrary length to avoid using just "**" or very short things as titles
            page_title = extracted_title
            page_text_lines = lines[1:] # Use subsequent lines for text body
            if not page_text_lines: # If only title line existed
                # page_text_lines = [extracted_title] # Or some placeholder like "[Content under this title]"
                print(f"Warning: Page {idx} titled '{page_title}' has no further content lines. Using title as text or consider placeholder.")
                # For now, if no further lines, the text will be empty. This can be adjusted.
                pass 
    else:
        # Fallback if no **Title** found, use textwrap on the first line if it's substantial
        if lines[0] and len(lines[0]) > 10: # Avoid using very short first lines as titles
            page_title = textwrap.shorten(lines[0], width=60, placeholder="…") # Increased width slightly
        # else page_title remains "Page {idx}"

    full_text = " ".join(page_text_lines).strip()
    
    # If after processing, full_text is empty but we had a chapter title, maybe use title as text.
    if not full_text and title_match and page_title != f"Page {idx}":
        # This handles case where a page is ONLY a title like **Chapter End**
        # We can decide if this page should still be created or skipped.
        # For now, let's use the title as text if text would otherwise be empty.
        full_text = page_title 

    if not full_text: # Final check if text is still empty
        print(f"Warning: Page {idx} ultimately has no text content. Skipping.")
        continue

    pages.append({
        "id": idx,
        "title": page_title,
        "text": full_text
    })

with DEST.open("w", encoding='utf-8') as f:
    json.dump(pages, f, ensure_ascii=False, indent=2)

print(f"Saved {len(pages)} pages to {DEST}") 