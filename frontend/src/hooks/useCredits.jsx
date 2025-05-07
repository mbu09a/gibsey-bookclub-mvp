import { useState, useEffect } from 'react';

export function useCredits() {
  const [credits, setCredits] = useState(null);
  const [error, setError] = useState(null);
  const [isLoading, setIsLoading] = useState(false);

  const fetchCredits = async () => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await fetch('/api/v1/users/me');
      
      if (response.redirected && response.url.includes('/api/v1/onboard/welcome')) {
        window.location.href = response.url;
        return;
      }

      if (!response.ok) {
        if (response.status === 401) {
          console.warn('Not authenticated, cannot fetch credits.');
          setCredits(null);
        } else {
          try {
            const errData = await response.json();
            throw new Error(errData.detail || `Failed to fetch credits. Status: ${response.status}`);
          } catch (jsonError) {
            throw new Error(`Failed to fetch credits. Status: ${response.status}. Response not JSON.`);
          }
        }
        return;
      }
      const data = await response.json();
      setCredits(data.credits);
    } catch (err) {
      console.error("Error fetching credits:", err);
      setError(err.message || 'An error occurred while fetching credits.');
      setCredits(null);
    }
    setIsLoading(false);
  };

  useEffect(() => {
    fetchCredits();
  }, []); // Intentionally empty dependency array for initial fetch on mount

  return { credits, setCredits, fetchCredits, isLoading, error }; 
} 