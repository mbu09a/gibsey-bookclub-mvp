"""
Passage extraction and text slicing utilities for Memory RAG

Provides functions to extract relevant passages from text documents
with a focus on finding coherent, limited-length text chunks
"""
import re
import logging
from difflib import SequenceMatcher
from typing import List, Dict, Any, Tuple, Optional

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Constants
MAX_WORDS = 40  # Maximum number of words in a quote
MIN_WORDS = 10  # Minimum number of words in a quote for it to be considered valid
MAX_QUOTE_CHARS = 240  # Maximum characters in a quote (for display purposes)

def tokenize_text(text: str) -> List[str]:
    """
    Split text into words (tokens)

    Args:
        text: Input text to tokenize

    Returns:
        List of word tokens
    """
    # Simple word tokenization - split on whitespace
    return re.findall(r'\S+', text)

def split_into_sentences(text: str) -> List[str]:
    """
    Split text into sentences

    Args:
        text: Input text to split

    Returns:
        List of sentences
    """
    # Basic sentence splitting - not perfect but works for most cases
    # Handles common sentence-ending punctuation followed by space or newline
    sentences = re.split(r'(?<=[.!?])\s+', text)

    # Clean up sentences - remove empty strings and strip whitespace
    return [s.strip() for s in sentences if s.strip()]

def best_quote(query: str, text: str, max_words: int = MAX_WORDS) -> str:
    """
    Find the most relevant section of text related to the query.
    Slices the text to return a quote of max_words or less.

    Args:
        query: User's question or search term
        text: Full page text to extract quote from
        max_words: Maximum word count for the returned quote

    Returns:
        String containing the most relevant quote
    """
    if not text:
        return ""

    # Split text into sentences
    sentences = re.split(r'(?<=[.!?])\s+', text)

    # Edge case - very short text
    if len(sentences) <= 1:
        words = text.split()
        return " ".join(words[:min(max_words, len(words))])

    # Clean and normalize query
    query_clean = re.sub(r'[^\w\s]', '', query.lower())
    query_tokens = set(query_clean.split())

    # Score each sentence by how many query tokens it contains
    scored_sentences = []
    for sentence in sentences:
        sentence_clean = re.sub(r'[^\w\s]', '', sentence.lower())
        sentence_tokens = set(sentence_clean.split())

        # Calculate token overlap score
        common_tokens = query_tokens.intersection(sentence_tokens)
        if not common_tokens:
            continue

        # Score is ratio of common tokens to total tokens in query
        token_score = len(common_tokens) / len(query_tokens)

        # Also evaluate with sequence matcher for phrase similarity
        sequence_score = SequenceMatcher(None, query_clean, sentence_clean).ratio()

        # Combine scores - more weight to token overlap
        combined_score = (0.7 * token_score) + (0.3 * sequence_score)

        scored_sentences.append((sentence, combined_score))

    # If no sentences matched, just return the first sentence
    if not scored_sentences:
        words = sentences[0].split()
        return " ".join(words[:min(max_words, len(words))])

    # Sort by score and take the highest
    scored_sentences.sort(key=lambda x: x[1], reverse=True)
    best_sentence = scored_sentences[0][0]

    # If the sentence is short, try to include context
    if len(best_sentence.split()) < max_words / 2:
        # Find the index of the best sentence
        best_idx = sentences.index(best_sentence)

        # Include surrounding sentences if available
        start_idx = max(0, best_idx - 1)
        end_idx = min(len(sentences), best_idx + 2)  # +2 because slicing is exclusive
        context = " ".join(sentences[start_idx:end_idx])

        # Truncate to max_words if needed
        words = context.split()
        if len(words) > max_words:
            context = " ".join(words[:max_words])

        return context

    # Otherwise, just return the best sentence, truncated if necessary
    words = best_sentence.split()
    if len(words) > max_words:
        return " ".join(words[:max_words])

    return best_sentence

def find_passage_containing_query(text: str, query: str, max_words: int = MAX_WORDS) -> Tuple[str, float]:
    """
    Find the most relevant passage in the text that contains words from the query

    Args:
        text: The full text document
        query: The search query
        max_words: Maximum words in returned passage

    Returns:
        Tuple of (best_passage, relevance_score)
    """
    passage = best_quote(query, text, max_words)

    # Calculate a simple relevance score based on query token overlap
    query_tokens = set(re.sub(r'[^\w\s]', '', query.lower()).split())
    passage_tokens = set(re.sub(r'[^\w\s]', '', passage.lower()).split())

    common_tokens = query_tokens.intersection(passage_tokens)
    score = len(common_tokens) / len(query_tokens) if query_tokens else 0.1

    return passage, score

def extract_relevant_quotes(text: str, query: str, max_quotes: int = 1) -> List[Dict[str, Any]]:
    """
    Extract a list of relevant quotes from the text based on the query

    Args:
        text: The full text document
        query: The search query
        max_quotes: Maximum number of quotes to return

    Returns:
        List of dicts with quote text and relevance score
    """
    if not text or not query or max_quotes < 1:
        return []

    # Find the best passage
    best_passage, best_score = find_passage_containing_query(text, query, MAX_WORDS)

    # For now, just return the single best passage
    # Future enhancement: Extract multiple non-overlapping passages
    if best_passage:
        return [{
            "quote": best_passage,
            "score": best_score,
            "char_count": len(best_passage),
            "word_count": len(tokenize_text(best_passage))
        }]

    # Fallback: If no good match, return the beginning of the text
    fallback_tokens = tokenize_text(text)[:MAX_WORDS]
    fallback_text = ' '.join(fallback_tokens)

    return [{
        "quote": fallback_text,
        "score": 0.1,  # Low confidence score
        "char_count": len(fallback_text),
        "word_count": len(fallback_tokens)
    }]