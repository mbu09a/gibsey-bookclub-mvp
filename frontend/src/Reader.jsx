import React, { useState, useEffect, useCallback } from 'react';
import Page from './Page'; // Assuming Page.jsx is in the same directory
import AskBox from './AskBox'; // <--- Added import
import AnswerPane from './AnswerPane'; // <--- Added import
// We will add CreditsBadge here later (Day 4)

export default function Reader() {
  const [pid, setPid] = useState(1); // Current page ID
  const [pageData, setPageData] = useState(null);
  const [maxPageId, setMaxPageId] = useState(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);
  const [askError, setAskError] = useState(null); // Specific error for AskBox

  const [answerData, setAnswerData] = useState(null); // <--- Added state for answer

  // Fetch page data function
  const fetchPage = useCallback(async (currentPageId) => {
    setIsLoading(true);
    setError(null);
    setAskError(null); // Clear ask error when navigating
    setAnswerData(null); // Clear previous answer when navigating
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

  // Callback for AskBox
  const handleNewAnswer = (newAnswer, errMessage) => {
    if (errMessage) {
        setAskError(errMessage);
        setAnswerData(null); // Clear old answer on new error
    } else {
        setAnswerData(newAnswer);
        setAskError(null); // Clear previous ask error
        // Scroll to the top of the page to see the answer
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }
    // Credits will be handled by CreditsBadge component and /me endpoint later
    // If newAnswer contains credit info, App.jsx might need to be involved for a global credit state.
  };

  // Callback for AnswerPane to jump to a page
  const jumpToPageId = useCallback((newPageId) => {
    if (newPageId >= 1 && (maxPageId === null || newPageId <= maxPageId)) {
      setPid(newPageId);
    }
  }, [maxPageId]);

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
      
      {/* Ask UI components added here */}
      {!isLoading && pageData && (
        <>
          <AskBox onAnswer={handleNewAnswer} />
          {askError && <p className="mt-2 text-sm text-center text-red-600 dark:text-red-400">Error from AskBox: {askError}</p>}
          <AnswerPane answerData={answerData} setPageId={jumpToPageId} />
        </>
      )}
    </div>
  );
} 