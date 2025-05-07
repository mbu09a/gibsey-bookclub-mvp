import React, { useState, useEffect, useCallback } from 'react';
import Page from './Page'; // Assuming Page.jsx is in the same directory
import AskBox from './AskBox'; // <--- Added import
import AnswerPane from './AnswerPane'; // <--- Added import
import CreditsBadge, { useCredits } from './CreditsBadge'; // <--- Added CreditsBadge and useCredits
// We will add CreditsBadge here later (Day 4)

export default function Reader({ initialPid = 1 }) {
  const [pid, setPid] = useState(initialPid); // <--- Use initialPid for useState
  const [pageData, setPageData] = useState(null);
  const [maxPageId, setMaxPageId] = useState(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);
  const [askError, setAskError] = useState(null); // Specific error for AskBox

  const [answerData, setAnswerData] = useState(null); // <--- Added state for answer

  const { credits, setCredits, fetchCredits } = useCredits(); // <--- Use the hook

  // State for Save Page functionality (moved from Page.jsx)
  const [isPageSaved, setIsPageSaved] = useState(false);
  const [pageSaveError, setPageSaveError] = useState(null);
  const [isPageSaving, setIsPageSaving] = useState(false);

  const fetchPage = useCallback(async (currentPageId) => {
    if (typeof currentPageId !== 'number' || currentPageId < 1) {
        console.error("FetchPage called with invalid ID:", currentPageId);
        setError("Invalid page number requested.");
        setPageData(null);
        setIsLoading(false);
        return;
    }
    setIsLoading(true);
    setError(null);
    setAskError(null);
    setAnswerData(null);
    setIsPageSaved(false); // Reset save status for new page
    setPageSaveError(null);
    try {
      const response = await fetch(`/api/v1/page/${currentPageId}`);
      if (!response.ok) {
        if (response.status === 401) {
            setError('Authentication failed. Please login again.');
            setCredits(null); 
        } else if (response.status === 404) {
            const errData = await response.json();
            setError(errData.detail || `Page ${currentPageId} not found.`);
        } else {
            throw new Error(`Failed to fetch page data. Status: ${response.status}`);
        }
        setPageData(null);
        return;
      }
      const data = await response.json();
      setPageData(data);
      if (data.max_page_id) {
        setMaxPageId(data.max_page_id);
      }
      // After fetching a page, one might check if it's already in the vault here
      // and set setIsPageSaved(true) if it is. For MVP, backend handles duplicates.
    } catch (err) {
      console.error("Error fetching page:", err);
      setError(err.message || 'An unexpected error occurred.');
      setPageData(null);
    }
    setIsLoading(false);
  }, [setCredits]);

  // Effect to update internal pid if initialPid prop changes (e.g. from Vault navigation)
  useEffect(() => {
    setPid(initialPid);
  }, [initialPid]);

  // Effect to fetch page whenever our internal pid changes
  useEffect(() => {
    fetchPage(pid);
  }, [pid, fetchPage]);

  const goToNextPage = () => {
    if (maxPageId === null || pid < maxPageId) {
      setPid((currentPid) => currentPid + 1);
    }
  };

  const goToPrevPage = () => {
    setPid((currentPid) => Math.max(1, currentPid - 1));
  };

  // Callback for AskBox
  const handleNewAnswer = (newAnswer, errMessage) => {
    if (errMessage) {
        setAskError(errMessage);
        setAnswerData(null);
    } else {
        setAnswerData(newAnswer);
        setAskError(null);
        if (newAnswer && typeof newAnswer.credits !== 'undefined') {
            setCredits(newAnswer.credits);
        }
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

  // Moved from Page.jsx
  const handleSaveCurrentPage = async () => {
    if (!pageData || typeof pageData.id === 'undefined') {
      setPageSaveError("Page ID is missing, cannot save.");
      return;
    }
    setIsPageSaving(true);
    setPageSaveError(null);
    try {
      const response = await fetch('/api/v1/vault/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ page_id: pageData.id }),
      });
      const result = await response.json();
      if (response.ok) {
        setIsPageSaved(true);
        if (result.new_credits !== null && typeof result.new_credits !== 'undefined') {
          setCredits(result.new_credits); // Update credits from save response
        }
      } else if (response.status === 409) { // Conflict - already saved
        setIsPageSaved(true); 
        setPageSaveError(result.detail || "Already in vault.");
      } else {
        throw new Error(result.detail || `Failed to save page. Status: ${response.status}`);
      }
    } catch (err) {
      console.error("Error saving page:", err);
      setPageSaveError(err.message || "Could not save page.");
    }
    setIsPageSaving(false);
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
        <div className="flex items-center gap-4">
            <CreditsBadge credits={credits} />
            <button 
              onClick={goToNextPage} 
              disabled={(maxPageId !== null && pid >= maxPageId) || isLoading}
              className="px-4 py-2 border rounded-md bg-blue-500 text-white hover:bg-blue-600 disabled:bg-gray-300 dark:disabled:bg-gray-600 transition-colors"
              aria-label="Next page"
            >
              Next ▶
            </button>
        </div>
        {/* DarkToggle and CreditsBadge will go here or in a main nav bar */}
      </nav>

      {isLoading && <p style={{ textAlign: 'center', padding: '20px' }}>Loading...</p>}
      {error && <p style={{ textAlign: 'center', padding: '20px', color: 'red' }}>Error: {error}</p>}
      
      {!isLoading && !error && pageData && 
        <Page 
          pageData={pageData} 
          onSavePage={handleSaveCurrentPage} // Pass down save handler
          isSaved={isPageSaved} 
          isSaving={isPageSaving} 
          saveError={pageSaveError} 
        />
      }
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