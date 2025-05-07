import React from 'react';

export default function Footer() {
  const currentYear = new Date().getFullYear();

  return (
    <footer className="w-full py-6 px-4 text-center text-sm text-gray-500 dark:text-gray-400 border-t border-gray-200 dark:border-gray-700 mt-auto bg-gray-50 dark:bg-gray-800">
      <div className="max-w-4xl mx-auto">
        <p className="mb-2">
          <a
            href="/api/v1/ledger.csv" // Points to the backend endpoint for CSV download
            target="_blank" // Open in new tab, though it will likely download
            rel="noopener noreferrer" // Security best practice for target="_blank"
            className="hover:underline text-blue-600 dark:hover:text-blue-400"
          >
            Community Ledger (CSV)
          </a>
          <span className="mx-2">|</span>
          <a 
            href="/BUG_REPORT.md" // Assuming BUG_REPORT.md will be in public or served
            target="_blank"
            rel="noopener noreferrer"
            className="hover:underline text-blue-600 dark:hover:text-blue-400"
          >
            Report a Bug
          </a>
        </p>
        <p>
          &copy; {currentYear} Gibsey Bookclub. "Receive curiosity as a gift; offer insight in return."
        </p>
      </div>
    </footer>
  );
} 