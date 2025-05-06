import React, { useState } from 'react';

export default function Login() {
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState(""); // For user feedback

  async function handleSubmit(event) {
    event.preventDefault();
    setMessage(""); // Clear previous messages

    if (!email.trim()) {
      setMessage("Please enter an email address.");
      return;
    }

    const formData = new FormData();
    formData.append('email', email);
    // formData.append('name', 'Reader'); // Name defaults to 'Reader' on the backend

    try {
      const response = await fetch('/api/v1/login', { // Updated to /api/v1/login
        method: 'POST',
        body: formData,
      });

      const data = await response.json();

      if (response.ok && data.ok) {
        setMessage(`Login successful! User ID: ${data.user_id}. Redirecting...`);
        // In a full React app with routing (e.g., React Router):
        // navigate('/reader'); 
        // For now, simple redirect:
        window.location.href = "/welcome"; // Redirect to /welcome first as per Day 7
      } else {
        setMessage(data.message || "Login failed. Please try again.");
      }
    } catch (error) {
      console.error("Login request failed:", error);
      setMessage("An error occurred during login. Please check the console.");
    }
  }

  return (
    <div style={{ maxWidth: '400px', margin: '50px auto', padding: '20px', border: '1px solid #ccc', borderRadius: '8px' }}>
      <h1 style={{ textAlign: 'center', marginBottom: '20px' }}>Sign in to Gibsey</h1>
      <form onSubmit={handleSubmit}>
        <div style={{ marginBottom: '15px' }}>
          <label htmlFor="email" style={{ display: 'block', marginBottom: '5px' }}>Email address:</label>
          <input
            type="email"
            id="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            required
            style={{ width: '100%', padding: '10px', border: '1px solid #ccc', borderRadius: '4px' }}
          />
        </div>
        <button 
          type="submit" 
          style={{
            width: '100%', 
            padding: '10px', 
            backgroundColor: '#007bff', 
            color: 'white', 
            border: 'none', 
            borderRadius: '4px', 
            cursor: 'pointer'
          }}
        >
          Enter
        </button>
      </form>
      {message && <p style={{ marginTop: '15px', textAlign: 'center', color: message.startsWith('Login successful') ? 'green' : 'red' }}>{message}</p>}
    </div>
  );
}

// To use this component, you would typically render it within a React application.
// For example, in an App.jsx or similar entry point:
// import React from 'react';
// import ReactDOM from 'react-dom/client';
// import Login from './Login'; // Assuming Login.jsx is in the same directory
//
// const root = ReactDOM.createRoot(document.getElementById('root'));
// root.render(
//   <React.StrictMode>
//     <Login />
//   </React.StrictMode>
// );
// You would also need an index.html file with a <div id="root"></div> 