import React, { useState, useEffect, useCallback } from 'react';

export default function Vault({ onSelectPage }) {
  const [savedEntries, setSavedEntries] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);

  const fetchVaultEntries = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await fetch('/api/v1/vault');
      if (!response.ok) {
        if (response.status === 401) {
            setError("Authentication required to view vault. Please login.");
        } else {
            const errData = await response.json();
            throw new Error(errData.detail || `Failed to fetch vault. Status: ${response.status}`);
        }
        setSavedEntries([]);
        return;
      }
      const data = await response.json();
      setSavedEntries(data || []);
    } catch (err) {
      console.error("Error fetching vault entries:", err);
      setError(err.message || "Could not fetch vault entries.");
      setSavedEntries([]);
    }
    setIsLoading(false);
  }, []);

  useEffect(() => {
    fetchVaultEntries();
  }, [fetchVaultEntries]);

  const handlePageLinkClick = (pageId) => {
    if (onSelectPage) {
      onSelectPage(pageId);
    }
  };

  if (isLoading) {
    return <p className="text-center p-8">Loading your vault...</p>;
  }

  if (error) {
    return <p className="text-center p-8 text-red-600">Error: {error}</p>;
  }

  return (
    <div className="max-w-3xl mx-auto p-4 sm:p-6 lg:p-8">
      <div className="flex justify-between items-center mb-6 pb-3 border-b border-gray-300 dark:border-gray-700">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white">My Vault</h1>
        <button 
            onClick={fetchVaultEntries} 
            disabled={isLoading}
            className="px-4 py-2 text-sm border rounded-md bg-gray-100 hover:bg-gray-200 dark:bg-gray-700 dark:hover:bg-gray-600 disabled:opacity-50 transition-colors"
            title="Refresh vault entries"
        >
            ↻ Refresh
        </button>
      </div>

      {savedEntries.length === 0 && (
        <p className="text-center text-gray-500 dark:text-gray-400 py-10">
          You haven't saved any passages yet. Use the "💾 Save" button on a page to add it to your vault.
        </p>
      )}

      <ul className="space-y-4">
        {savedEntries.map((entry) => (
          <li key={entry.id} className="p-4 border border-gray-200 dark:border-gray-700 rounded-lg shadow-sm hover:shadow-md transition-shadow bg-white dark:bg-gray-800">
            <button
              onClick={() => handlePageLinkClick(entry.page_id)}
              className="text-lg font-semibold text-blue-600 dark:text-blue-400 hover:underline focus:outline-none"
            >
              {entry.title || `Page ${entry.page_id}`}
            </button>
            {entry.note && (
              <p className="mt-1 text-sm italic text-gray-600 dark:text-gray-400">Note: {entry.note}</p>
            )}
            <p className="mt-1 text-xs text-gray-500 dark:text-gray-500">
              Saved on: {new Date(entry.ts * 1000).toLocaleDateString()} {new Date(entry.ts * 1000).toLocaleTimeString()}
            </p>
          </li>
        ))}
      </ul>
    </div>
  );
} 