import React, { useState } from 'react';

export default function AskBox({ onAnswer }) {
  const [query, setQuery] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleSubmit = async (event) => {
    event.preventDefault();
    if (!query.trim()) {
      setError("Please enter a question.");
      return;
    }
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/v1/ask', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          // Cookies should be sent automatically by the browser due to `credentials: 'include'` 
          // if it were needed for cross-origin, but same-origin with proxy doesn't require it as much.
          // FastAPI's Depends(Cookie(...)) handles cookie extraction on the backend.
        },
        body: JSON.stringify({ query: query }),
      });

      const data = await response.json();

      if (!response.ok) {
        if (response.status === 401) {
            setError("Authentication required. Please login again.");
            // Optionally, redirect to login or show a login prompt
        } else {
            throw new Error(data.detail || `API Error: ${response.status}`);
        }
        if (onAnswer) onAnswer(null, data.detail || `Failed to get answer. Status: ${response.status}`);
        return;
      }
      
      if (onAnswer) {
        onAnswer(data, null); // Pass data to parent, clear previous error
      }
      setQuery(""); // Clear input after successful submission

    } catch (err) {
      console.error("Error submitting question:", err);
      setError(err.message || "An unexpected error occurred.");
      if (onAnswer) onAnswer(null, err.message || "An unexpected error occurred.");
    }
    setIsLoading(false);
  };

  return (
    <form onSubmit={handleSubmit} className="mt-6 p-4 border border-gray-300 dark:border-gray-700 rounded-lg shadow-md bg-white dark:bg-gray-800">
      <label htmlFor="ask-query" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
        Ask the Gibsey Guide:
      </label>
      <div className="flex flex-col sm:flex-row gap-2">
        <input
          id="ask-query"
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="What is the meaning of..."
          disabled={isLoading}
          className="flex-grow mt-1 block w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm dark:bg-gray-700 dark:text-white disabled:bg-gray-100 dark:disabled:bg-gray-700"
        />
        <button
          type="submit"
          disabled={isLoading}
          className="mt-1 sm:mt-0 px-6 py-3 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 disabled:bg-gray-400 dark:disabled:bg-gray-500 transition-colors whitespace-nowrap"
        >
          {isLoading ? 'Asking...' : 'Ask Gibsey'}
        </button>
      </div>
      {error && <p className="mt-2 text-sm text-red-600 dark:text-red-400">Error: {error}</p>}
    </form>
  );
} 