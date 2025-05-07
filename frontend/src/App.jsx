import React, { useState, useEffect, useCallback } from 'react';
import Login from './Login';
import Reader from './Reader';
import Vault from './Vault';
// import Welcome from './Welcome'; // We'll add this for Day 7 onboarding
import Footer from './Footer';
import DarkToggle from './DarkToggle';
import './App.css'; // Standard Vite App CSS, can be modified/removed

// Helper to check for a cookie
function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
    return null;
}

function App() {
  // Views: 'login', 'reader', 'vault'
  // Welcome screen is handled by API redirect now.
  const [currentView, setCurrentView] = useState('login'); 
  const [readerPageId, setReaderPageId] = useState(1);
  const [isLoggedIn, setIsLoggedIn] = useState(false); // Manage login state

  // Check session and welcome status on initial load or when view might change
  useEffect(() => {
    async function checkUserStatus() {
      try {
        const response = await fetch('/api/v1/users/me');
        if (response.ok) {
          setIsLoggedIn(true);
          // If logged in, and seen_welcome cookie is set by server after /onboard/enter,
          // we can default to reader. If API redirects to /api/v1/onboard/welcome,
          // browser will follow that. If it doesn't (e.g. already seen_welcome), /me succeeds.
          if (getCookie('seen_welcome')) {
            setCurrentView('reader'); 
          } else {
            // This case implies /me succeeded (so logged in) but no seen_welcome cookie.
            // The API should have redirected. If we land here, it means API didn't redirect
            // (e.g. if seen_welcome was checked *after* successful user fetch in get_current_user).
            // For now, if /me is ok, assume welcome was handled or seen.
            // The critical redirect to HTML welcome page is done by API if needed.
            setCurrentView('reader'); 
          }
        } else {
          setIsLoggedIn(false);
          setCurrentView('login');
        }
      } catch (error) {
        setIsLoggedIn(false);
        setCurrentView('login');
      }
    }
    checkUserStatus();
  }, []); // Runs once on mount

  const handleLoginSuccess = () => {
    setIsLoggedIn(true);
    // After login, the API redirect in get_current_user for the first protected call
    // (e.g., from Reader's /me or /page/1 call) will handle showing the HTML welcome page
    // if the 'seen_welcome' cookie is not set. Once 'seen_welcome' is set by /onboard/enter,
    // user will be redirected to '/' by the backend, and this App component will re-evaluate.
    // So, we can optimistically try to go to reader here.
    setCurrentView('reader'); 
    setReaderPageId(1);
  };

  const handleLogout = async () => {
    // We don't have a /logout API endpoint yet that clears the HTTPOnly cookie.
    // For now, simulate logout by clearing React state and any client-side session info.
    // To truly logout, the gibsey_sid cookie needs to be cleared (usually by backend setting max-age=0)
    setIsLoggedIn(false);
    setCurrentView('login');
    // document.cookie = "gibsey_sid=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;"; // JS can't clear HttpOnly
    // document.cookie = "seen_welcome=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;"; // Can clear this one
    console.log("Simulated logout. True logout requires backend to clear HttpOnly session cookie.");
  };

  const navigateToVault = () => { setCurrentView('vault'); };
  const navigateToReader = useCallback((pageId = 1) => {
    setReaderPageId(pageId);
    setCurrentView('reader');
  }, []);

  let viewToRender;
  let navControls = null;

  if (!isLoggedIn || currentView === 'login') {
    viewToRender = <Login onLoginSuccess={handleLoginSuccess} />;
  } else {
    navControls = (
      <div className="p-4 bg-gray-200 dark:bg-gray-700 flex flex-wrap justify-center items-center gap-y-2 sm:gap-y-0 space-x-4 mb-4 rounded-md shadow">
        <button onClick={() => navigateToReader()} disabled={currentView === 'reader'} className="px-4 py-2 border rounded-md bg-indigo-500 text-white hover:bg-indigo-600 disabled:bg-gray-400 transition-colors">Reader</button>
        <button onClick={navigateToVault} disabled={currentView === 'vault'} className="px-4 py-2 border rounded-md bg-indigo-500 text-white hover:bg-indigo-600 disabled:bg-gray-400 transition-colors">My Vault</button>
        <DarkToggle />
        <button onClick={handleLogout} className="px-4 py-2 border rounded-md bg-red-500 text-white hover:bg-red-600 transition-colors">Logout (Simulated)</button>
      </div>
    );
    switch (currentView) {
      case 'reader':
        viewToRender = <Reader key={readerPageId} initialPid={readerPageId} />;
        break;
      case 'vault':
        viewToRender = <Vault onSelectPage={navigateToReader} />;
        break;
      default: // Default to reader if logged in but view is unexpected
        viewToRender = <Reader key={readerPageId} initialPid={readerPageId} />;
    }
  }

  return (
    <div className="App min-h-screen flex flex-col">
      {navControls} 
      <main className="flex-grow container mx-auto px-4 py-2">
        {viewToRender}
      </main>
      <Footer />
    </div>
  );
}

export default App;
