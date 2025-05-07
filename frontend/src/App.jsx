import React, { useState, useEffect, useCallback } from 'react';
import Login from './Login';
import Reader from './Reader';
import Vault from './Vault';
// import Welcome from './Welcome'; // We'll add this for Day 7 onboarding
import Footer from './Footer';
import './App.css'; // Standard Vite App CSS, can be modified/removed

function App() {
  // Simple view management: 'login', 'welcome', 'reader'
  // We will check for an existing valid session to bypass login later
  const [currentView, setCurrentView] = useState('login'); 
  const [readerPageId, setReaderPageId] = useState(1); // To control reader's page from Vault

  // This effect could be used to check for an existing valid session on component mount
  // For now, we always start at login for simplicity in Day 2.
  // useEffect(() => {
  //   async function checkSession() {
  //     try {
  //       const response = await fetch('/api/v1/users/me'); // Test if already logged in
  //       if (response.ok) {
  //         setCurrentView('reader'); // Or 'welcome' if not seen before
  //       } else {
  //         setCurrentView('login');
  //       }
  //     } catch (error) {
  //       setCurrentView('login'); // Default to login on error
  //     }
  //   }
  //   checkSession();
  // }, []);

  const handleLoginSuccess = () => {
    // As per Day 7, new users go to /welcome first.
    // We'll need a way to know if welcome has been seen.
    // For Day 2, let's simplify and go directly to reader after login.
    // We will refine this with the /welcome flow from Day 7.
    // setCurrentView('welcome'); 
    setCurrentView('reader'); 
    setReaderPageId(1); // Reset to page 1 on new login
  };

  // const handleWelcomeComplete = () => {
  //   setCurrentView('reader');
  // };

  const navigateToVault = () => {
    setCurrentView('vault');
  };

  const navigateToReader = useCallback((pageId = 1) => {
    setReaderPageId(pageId);
    setCurrentView('reader');
  }, []);

  let viewToRender;
  let navControls = null;

  if (currentView === 'login') {
    viewToRender = <Login onLoginSuccess={handleLoginSuccess} />;
  } else {
    // Common navigation for authenticated views (Reader, Vault)
    navControls = (
      <div className="p-4 bg-gray-200 dark:bg-gray-700 text-center space-x-4 mb-4 rounded-md shadow">
        <button 
            onClick={() => navigateToReader()} 
            disabled={currentView === 'reader'}
            className="px-4 py-2 border rounded-md bg-indigo-500 text-white hover:bg-indigo-600 disabled:bg-gray-400 transition-colors"
        >
            Reader
        </button>
        <button 
            onClick={navigateToVault} 
            disabled={currentView === 'vault'}
            className="px-4 py-2 border rounded-md bg-indigo-500 text-white hover:bg-indigo-600 disabled:bg-gray-400 transition-colors"
        >
            My Vault
        </button>
        {/* Logout button could go here */}
      </div>
    );

    switch (currentView) {
      case 'reader':
        // Pass readerPageId to Reader if we want to control its initial pid from here
        // For now, Reader manages its own pid internally after initial mount
        // We could enhance Reader to take an initialPid prop if needed for deep linking from Vault
        viewToRender = <Reader key={readerPageId} initialPid={readerPageId} />;
        break;
      case 'vault':
        viewToRender = <Vault onSelectPage={navigateToReader} />;
        break;
      default: // Should not happen if logged in
        viewToRender = <Login onLoginSuccess={handleLoginSuccess} />;
    }
  }

  return (
    <div className="App min-h-screen flex flex-col">
      {/* Render navControls only if not on login view */}
      {currentView !== 'login' && navControls}
      <main className="flex-grow container mx-auto px-4 py-2">
        {viewToRender}
      </main>
      <Footer />
    </div>
  );
}

export default App;
