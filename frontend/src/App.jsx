import React, { useState, useEffect } from 'react';
import Login from './Login';
import Reader from './Reader';
// import Welcome from './Welcome'; // We'll add this for Day 7 onboarding
import './App.css'; // Standard Vite App CSS, can be modified/removed

function App() {
  // Simple view management: 'login', 'welcome', 'reader'
  // We will check for an existing valid session to bypass login later
  const [currentView, setCurrentView] = useState('login'); 

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
  };

  // const handleWelcomeComplete = () => {
  //   setCurrentView('reader');
  // };

  let viewToRender;
  switch (currentView) {
    case 'login':
      viewToRender = <Login onLoginSuccess={handleLoginSuccess} />;
      break;
    // case 'welcome':
    //   viewToRender = <Welcome onWelcomeComplete={handleWelcomeComplete} />;
    //   break;
    case 'reader':
      viewToRender = <Reader />;
      break;
    default:
      viewToRender = <Login onLoginSuccess={handleLoginSuccess} />;
  }

  return (
    <div className="App">
      {/* Navbar could go here later, outside the view switch */}
      {viewToRender}
    </div>
  );
}

export default App;
