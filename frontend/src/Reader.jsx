import React, { useState, useEffect, useCallback } from 'react';
import Page from './Page'; // Assuming Page.jsx is in the same directory
// We will add AskBox and AnswerPane here later (Day 3)
// We will add CreditsBadge here later (Day 4)

export default function Reader() {
  const [pid, setPid] = useState(1); // Current page ID
  const [pageData, setPageData] = useState(null);
  const [maxPageId, setMaxPageId] = useState(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);

  // Fetch page data function
  const fetchPage = useCallback(async (currentPageId) => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await fetch(`/api/v1/page/${currentPageId}`);
      if (!response.ok) {
        if (response.status === 401) {
            setError('Authentication failed. Please login again.');
            // Consider redirecting to login: window.location.href = '/login';
        } else if (response.status === 404) {
            const errData = await response.json();
            setError(errData.detail || `Page ${currentPageId} not found.`);
            // Reset to page 1 or last known good page if current pid is invalid
            // setPid(1); 
        } else {
            throw new Error(`Failed to fetch page data. Status: ${response.status}`);
        }
        setPageData(null); // Clear old page data on error
        return;
      }
      const data = await response.json();
      setPageData(data);
      if (data.max_page_id) {
        setMaxPageId(data.max_page_id);
      }
    } catch (err) {
      console.error("Error fetching page:", err);
      setError(err.message || 'An unexpected error occurred.');
      setPageData(null);
    }
    setIsLoading(false);
  }, []);

  // Effect to fetch page when pid changes
  useEffect(() => {
    fetchPage(pid);
  }, [pid, fetchPage]);

  const goToNextPage = () => {
    // Check against maxPageId before incrementing beyond the last page
    if (maxPageId === null || pid < maxPageId) {
      setPid((currentPid) => currentPid + 1);
    }
  };

  const goToPrevPage = () => {
    setPid((currentPid) => Math.max(1, currentPid - 1)); // Ensure pid doesn't go below 1
  };

  return (
    <div className="reader-container mx-auto max-w-4xl p-4 font-sans">
      <nav className="flex justify-between items-center p-4 bg-gray-100 dark:bg-gray-800 rounded-md shadow-md mb-6">
        <button 
          onClick={goToPrevPage} 
          disabled={pid === 1 || isLoading}
          className="px-4 py-2 border rounded-md bg-blue-500 text-white hover:bg-blue-600 disabled:bg-gray-300 dark:disabled:bg-gray-600 transition-colors"
          aria-label="Previous page"
        >
          ◀ Prev
        </button>
        <span className="text-lg font-semibold text-gray-700 dark:text-gray-200">
          Page {pid}{maxPageId ? ` of ${maxPageId}` : ''}
        </span>
        <button 
          onClick={goToNextPage} 
          disabled={(maxPageId !== null && pid >= maxPageId) || isLoading}
          className="px-4 py-2 border rounded-md bg-blue-500 text-white hover:bg-blue-600 disabled:bg-gray-300 dark:disabled:bg-gray-600 transition-colors"
          aria-label="Next page"
        >
          Next ▶
        </button>
        {/* DarkToggle and CreditsBadge will go here or in a main nav bar */}
      </nav>

      {isLoading && <p style={{ textAlign: 'center', padding: '20px' }}>Loading...</p>}
      {error && <p style={{ textAlign: 'center', padding: '20px', color: 'red' }}>Error: {error}</p>}
      
      {!isLoading && !error && pageData && <Page pageData={pageData} />}
      {!isLoading && !error && !pageData && <p style={{ textAlign: 'center', padding: '20px' }}>Page content will appear here.</p>} 
      
      {/* AskBox and AnswerPane will be added below the Page component later */}
    </div>
  );
} 