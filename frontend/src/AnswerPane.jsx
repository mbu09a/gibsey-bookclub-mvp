import React from 'react';

// Helper function to parse the answer string
function parseAnswerWithQuotes(answerString, onCitationClick) {
  if (!answerString) return [];

  const parts = [];
  let lastIndex = 0;

  // Regex to find embedded JSON quotes like: {"page_id":128,"loc":"p128-3","quote":"Natalie…"}
  // It looks for a curly brace, then "page_id", then captures the page_id digits,
  // then captures the quote content between "quote":".*?", making sure not to be too greedy.
  const quoteRegex = /\{\s*"page_id"\s*:\s*(\d+)\s*,\s*.*?"quote"\s*:\s*"(.*?)"\s*\}/g;

  let match;
  while ((match = quoteRegex.exec(answerString)) !== null) {
    // Add text part before the quote
    if (match.index > lastIndex) {
      parts.push(answerString.substring(lastIndex, match.index));
    }
    
    const pageId = parseInt(match[1], 10);
    const quoteText = match[2];

    // Add the clickable quote
    parts.push(
      <button 
        key={`citation-${pageId}-${match.index}`} 
        onClick={() => onCitationClick(pageId)}
        className="citation-link text-blue-600 dark:text-blue-400 hover:underline focus:outline-none focus:ring-2 focus:ring-blue-300 dark:focus:ring-blue-600 rounded px-1 py-0.5 bg-blue-50 dark:bg-gray-700 hover:bg-blue-100 dark:hover:bg-gray-600 transition-colors mx-0.5"
        title={`Jump to page ${pageId}`}
      >
        "...{quoteText}..."
      </button>
    );
    lastIndex = quoteRegex.lastIndex;
  }

  // Add any remaining text part after the last quote
  if (lastIndex < answerString.length) {
    parts.push(answerString.substring(lastIndex));
  }

  // The Day 3 plan shows a simpler regex and direct dangerouslySetInnerHTML.
  // This component-based approach is safer and more React-idiomatic.
  // We can refine the quote text display (e.g., how much of it to show as the link text).
  // For now, "...quote..." is a placeholder for the actual quote text within the button.

  // Wrap text parts in spans to ensure proper line breaks and whitespace handling
  return parts.map((part, index) => 
    typeof part === 'string' ? 
    <span key={`text-${index}`}>{part.split('\n').map((line, i) => <React.Fragment key={i}>{line}{i < part.split('\n').length - 1 && <br />}</React.Fragment>)}</span> : 
    part
  );
}

export default function AnswerPane({ answerData, setPageId }) {
  if (!answerData || !answerData.answer) {
    return null; // Don't render if no answer
  }

  const handleCitationClick = (pageId) => {
    if (setPageId) {
      setPageId(pageId);
      // Scroll to top of page or reader view after jump might be good UX
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
  };

  const parsedAnswer = parseAnswerWithQuotes(answerData.answer, handleCitationClick);

  return (
    <div className="mt-6 p-4 border border-gray-300 dark:border-gray-700 rounded-lg shadow-md bg-white dark:bg-gray-800">
      <h3 className="text-lg font-semibold text-gray-800 dark:text-gray-100 mb-2">Gibsey's Answer:</h3>
      <div className="prose dark:prose-invert max-w-none text-gray-700 dark:text-gray-300 whitespace-pre-line">
        {parsedAnswer}
      </div>
      {answerData.citations && answerData.citations.length > 0 && (
        <div className="mt-4 pt-3 border-t border-gray-200 dark:border-gray-700">
          <p className="text-sm text-gray-600 dark:text-gray-400">
            Cited pages: {answerData.citations.join(', ')}
            {/* We could make these clickable too if desired, though the inline links are primary */}
          </p>
        </div>
      )}
    </div>
  );
} 