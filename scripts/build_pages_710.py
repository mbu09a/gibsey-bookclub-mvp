import re, json, pathlib, textwrap, sys

PROJECT_ROOT = pathlib.Path(__file__).parent.parent
SRC_TEXT_FILE  = PROJECT_ROOT / "cleaned_normalised.txt"
DEST_JSON_FILE = PROJECT_ROOT / "data" / "pages_710.json"
DEST_JSON_FILE.parent.mkdir(parents=True, exist_ok=True)

# Based on your provided list and follow-up title preferences
# Structure: start_page, end_page, full_title_at_start, follow_up_title_format (can use {chapter_num}, {chapter_title})
# The script will also try to identify if the first line(s) of a page chunk match these titles.
PRIMARY_SECTION_DEFINITIONS = [
    {"s": 1,   "e": 8,   "full": "an author's preface", "follow": "an author's preface"},
    {"s": 9,   "e": 24,  "full": "London Fox Who Vertically Disintegrates", "follow": "London Fox Who Vertically Disintegrates"},
    {"s": 25,  "e": 57,  "full": "An Unexpected Disappearance: A Glyph Marrow Mystery- Chapter 1- The Queue and Station", "follow": "An Unexpected Disappearance Chapter 1"},
    {"s": 58,  "e": 74,  "full": "An Unexpected Disappearance: A Glyph Marrow Mystery- Chapter 2- The Tunnel", "follow": "An Unexpected Disappearance Chapter 2"},
    {"s": 75,  "e": 109, "full": "An Unexpected Disappearance: A Glyph Marrow Mystery- Chapter 3- The First Ascent", "follow": "An Unexpected Disappearance Chapter 3"},
    {"s": 110, "e": 141, "full": "An Unexpected Disappearance- Chapter 4- The Flooded Town", "follow": "An Unexpected Disappearance Chapter 4"},
    {"s": 142, "e": 176, "full": "An Unexpected Disappearance:A Glyph Marrow Mystery- Chapter 5- The Waterfall", "follow": "An Unexpected Disappearance Chapter 5"},
    {"s": 177, "e": 203, "full": "An Unexpected Disappearance: A Glyph Marrow Mystery- Chapter 6- The Tunneled Vision", "follow": "An Unexpected Disappearance Chapter 6"},
    {"s": 204, "e": 217, "full": "An Expected Appearance: A Phillip Bafflemint Noir- Chapter 1- The Tunneled Vision", "follow": "An Expected Appearance Chapter 1"},
    {"s": 218, "e": 228, "full": "An Expected Appearance: A Phillip Bafflemint Noir- Chapter 2- The Flooded House", "follow": "An Expected Appearance Chapter 2"},
    {"s": 229, "e": 235, "full": "An Expected Appearance: A Phllip Bafflemint Noir- Chapter 3- The First Descent", "follow": "An Expected Appearance Chapter 3"},
    {"s": 236, "e": 307, "full": "Jacklyn Variance, The Watcher, is Watched", "follow": "Jacklyn Variance, The Watcher, is Watched"},
    {"s": 308, "e": 354, "full": "The Last Auteur", "follow": "The Last Auteur"},
    {"s": 355, "e": 380, "full": "Gibseyan Mysticism and its Symbolism", "follow": "Gibseyan Mysticism and its Symbolism"},
    {"s": 381, "e": 385, "full": "Princhetta Who Thinks Herself Alive", "follow": "Princhetta Who Thinks Herself Alive"},
    {"s": 386, "e": 411, "full": "Petition for Bankruptcy- Chapter 11, by Perdition Books, a Subsidiary of Skingraft Publishing", "follow": "Petition for Bankruptcy- Chapter 11"},
    {"s": 412, "e": 432, "full": "The Tempestuous Storm", "follow": "The Tempestuous Storm"},
    {"s": 433, "e": 487, "full": "Arieol Owlist Who Wants to Achieve Agency", "follow": "Arieol Owlist Who Wants to Achieve Agency"},
    {"s": 488, "e": 500, "full": "The Biggest Shit of All Time", "follow": "The Biggest Shit of All Time"},
    {"s": 501, "e": 526, "full": "An Expected Appearance: A Phillip Bafflemint Noir- Chapter 4- The Slip and The Mistake", "follow": "An Expected Appearance Chapter 4"},
    {"s": 527, "e": 545, "full": "An Expected Appearance: A Phillip Bafflemint Noir- Chapter 5- The Stations", "follow": "An Expected Appearance Chapter 5"},
    {"s": 546, "e": 564, "full": "An Expected Apperance: A Phillip Bafflemint Noir- Chapter 6- The Third Ascent", "follow": "An Expected Appearance Chapter 6"},
    {"s": 565, "e": 584, "full": "An Unexpected Disappearance: A Glyph Marrow Mystery- Chapter 7- The Rainbows", "follow": "An Unexpected Disappearance Chapter 7"},
    {"s": 585, "e": 603, "full": "An Unexpected Disappearance: A Glyph Marrow Mystery- Chapter 8- The Caves", "follow": "An Unexpected Disappearance Chapter 8"},
    {"s": 604, "e": 611, "full": "An Unexpected Disappearance- Chapter 9- The Third Ascent", "follow": "An Unexpected Disappearance Chapter 9"}, # Corrected typo in original: A Glyph Marrow Mystery was missing
    {"s": 612, "e": 623, "full": "An Unexpected Disappearance: A Glyph Marrow Mystery- Chapter 10- The Geyser", "follow": "An Unexpected Disappearance Chapter 10"},
    {"s": 624, "e": 641, "full": "An Unexpected Disappearance: A Glyph Marrow Mystery- Chapter 11- The Return to the Station", "follow": "An Unexpected Disappearance Chapter 11"},
    {"s": 642, "e": 677, "full": "Todd Fishbone Who Dreams of Synchronistic Extraction", "follow": "Todd Fishbone Who Dreams of Synchronistic Extraction"},
    {"s": 678, "e": 710, "full": "The Author's Preface", "follow": "The Author's Preface"} # Assuming this is distinct from the first preface section
]

print(f"Reading from: {SRC_TEXT_FILE}")
if not SRC_TEXT_FILE.exists():
    print(f"ERROR: Source file {SRC_TEXT_FILE} not found.")
    sys.exit(1)

raw_text_content = SRC_TEXT_FILE.read_text(encoding='utf-8')
text_chunks = re.split(r"###Page \d+###", raw_text_content)

processed_page_chunks = []
if text_chunks and text_chunks[0].strip() == "":
    processed_page_chunks = text_chunks[1:]
elif text_chunks and len(text_chunks) > 1:
    processed_page_chunks = text_chunks[1:]
else:
    print("ERROR: No page content found after splitting by page markers.")
    sys.exit(1)

print(f"Processing {len(processed_page_chunks)} text chunks for pages.")

final_pages_data = []
# Regex to detect if a line is a potential title line (starts with ** and ends with **)
# This is a simple check; more complex title lines might need more parsing.
TITLE_LINE_PATTERN = re.compile(r"^\*\*(.+?)\*\*$")

for page_idx_from_file, current_chunk_text in enumerate(processed_page_chunks, 1):
    current_chunk_text = current_chunk_text.strip()
    content_lines = [line.strip() for line in current_chunk_text.splitlines() if line.strip()]

    if not content_lines:
        print(f"Warning: Page {page_idx_from_file} is empty after stripping. Skipping.")
        continue

    # Determine section and title
    current_section_title = f"Page {page_idx_from_file}" # Default
    is_first_page_of_section = False
    lines_for_text_body = list(content_lines) # Make a copy to modify

    for section_def in PRIMARY_SECTION_DEFINITIONS:
        if section_def["s"] <= page_idx_from_file <= section_def["e"]:
            if page_idx_from_file == section_def["s"]:
                current_section_title = section_def["full"]
                is_first_page_of_section = True
                # Attempt to remove the title line from the text body if it matches
                # This needs to be robust to how titles appear in cleaned_normalised.txt
                # For example, if the title is **Title**, we remove that line.
                # If it's "**Series** **Chapter**", it's more complex.
                # For now, a simple check if first content line matches a part of the full title.
                first_line_lower = content_lines[0].lower()
                # Check based on known title structures like **Title** or **Series** **Chapter**
                title_marker_match = TITLE_LINE_PATTERN.match(content_lines[0])
                if title_marker_match:
                    # If first line is a **Marked Title**, remove it from text body
                    lines_for_text_body = content_lines[1:]
                elif section_def["full"].lower().startswith(first_line_lower) and len(first_line_lower) > 10:
                     # If the first line seems to be the start of the full title (and not a generic line)
                     lines_for_text_body = content_lines[1:]
            else:
                current_section_title = section_def["follow"]
            break # Found the section
    
    final_page_title = f"Page {page_idx_from_file} - {current_section_title}"
    page_text_content = " ".join(lines_for_text_body).strip()

    if not page_text_content and is_first_page_of_section:
        # If a section's first page ended up with no text after title removal,
        # use the title as text to avoid empty pages for title-only pages.
        page_text_content = current_section_title 

    if not page_text_content:
        print(f"Warning: Page {page_idx_from_file} (Title: '{final_page_title}') has no text content. Skipping.")
        continue

    final_pages_data.append({
        "id": page_idx_from_file,
        "title": final_page_title,
        "text": page_text_content
    })

with DEST_JSON_FILE.open("w", encoding='utf-8') as f:
    json.dump(final_pages_data, f, ensure_ascii=False, indent=2)

print(f"Saved {len(final_pages_data)} pages to {DEST_JSON_FILE}") 