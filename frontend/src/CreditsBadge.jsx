import React, { useState, useEffect } from 'react';

// Custom hook to manage credits state and fetching
export function useCredits() {
  const [credits, setCredits] = useState(null); // Start with null to indicate loading/not fetched
  const [error, setError] = useState(null);
  const [isLoading, setIsLoading] = useState(false);

  const fetchCredits = async () => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await fetch('/api/v1/users/me');
      if (!response.ok) {
        if (response.status === 401) {
          // Don't set an error here, as it might be normal for a non-logged-in user
          // The component displaying the badge can decide what to do (e.g., show nothing)
          console.warn('Not authenticated, cannot fetch credits.');
          setCredits(null); // Ensure credits are null if not authenticated
        } else {
          const errData = await response.json();
          throw new Error(errData.detail || `Failed to fetch credits. Status: ${response.status}`);
        }
        return; // Important to return here if response not ok
      }
      const data = await response.json();
      setCredits(data.credits);
    } catch (err) {
      console.error("Error fetching credits:", err);
      setError(err.message || 'An error occurred while fetching credits.');
      setCredits(null); // Reset credits on error
    }
    setIsLoading(false);
  };

  useEffect(() => {
    fetchCredits(); // Fetch credits on initial mount
  }, []);

  // Return setCredits to allow manual updates, e.g., after an action earns credits
  // Also return isLoading and error for more granular UI control if needed
  return { credits, setCredits, fetchCredits, isLoading, error }; 
}

// CreditsBadge presentational component
export default function CreditsBadge({ credits }) {
  // If credits is null (initial load, not fetched, or error) or undefined, don't show anything or show loading
  // For this MVP, if credits is null (e.g. not logged in), we simply don't render the badge.
  if (credits === null || typeof credits === 'undefined') {
    return null; 
  }

  // Basic styling, no Tailwind, no SVG for now
  return (
    <span 
      style={{ 
        padding: '4px 8px', 
        borderRadius: '12px', 
        backgroundColor: '#DCFCE7', /* emerald-100 like */
        color: '#065F46', /* emerald-800 like */
        fontSize: '0.875rem', 
        fontWeight: '600',
        border: '1px solid #6EE7B7' /* emerald-300 like */
      }}
      title={`${credits} credits`}
    >
      Credits: {credits}
    </span>
  );
} 