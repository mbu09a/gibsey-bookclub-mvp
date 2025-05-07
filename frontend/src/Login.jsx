import React, { useState } from 'react';

// We'll pass a function to call on successful login
export default function Login({ onLoginSuccess }) { 
  const [email, setEmail] = useState("");
  const [name, setName] = useState(""); // Optional: allow user to set name
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState("");

  async function handleSubmit(event) {
    event.preventDefault();
    setMessage("");
    setIsLoading(true);

    if (!email.trim()) {
      setMessage("Please enter an email address.");
      setIsLoading(false);
      return;
    }

    const formData = new FormData();
    formData.append('email', email);
    if (name.trim()) {
      formData.append('name', name.trim());
    }
    // Backend defaults name to 'Reader' if not provided

    try {
      const response = await fetch('/api/v1/login', {
        method: 'POST',
        body: formData,
      });
      const data = await response.json();

      if (response.ok && data.ok) {
        // setMessage(`Login successful! User ID: ${data.user_id}. Redirecting...`);
        if (onLoginSuccess) {
          onLoginSuccess(); // Callback to parent to handle routing/state change
        }
      } else {
        setMessage(data.message || "Login failed. Please try again.");
      }
    } catch (error) {
      console.error("Login request failed:", error);
      setMessage("An error occurred during login. Please check the console.");
    }
    setIsLoading(false);
  }

  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gray-50 dark:bg-gray-900 p-4">
      <div className="w-full max-w-md p-8 space-y-6 bg-white dark:bg-gray-800 rounded-xl shadow-lg">
        <h1 className="text-3xl font-bold text-center text-gray-900 dark:text-white">Sign in to Gibsey</h1>
        <form onSubmit={handleSubmit} className="space-y-6">
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Email address
            </label>
            <input
              type="email"
              id="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              required
              className="mt-1 block w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm dark:bg-gray-700 dark:text-white"
            />
          </div>
          <div>
            <label htmlFor="name" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Name (Optional)
            </label>
            <input
              type="text"
              id="name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Your Name"
              className="mt-1 block w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm dark:bg-gray-700 dark:text-white"
            />
          </div>
          <div>
            <button
              type="submit"
              disabled={isLoading}
              className="w-full flex justify-center py-3 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:bg-gray-400 dark:disabled:bg-gray-500 transition-colors"
            >
              {isLoading ? 'Signing in...' : 'Enter'}
            </button>
          </div>
        </form>
        {message && (
          <p className={`mt-4 text-center text-sm ${message.includes('successful') ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}`}>
            {message}
          </p>
        )}
      </div>
    </div>
  );
} 