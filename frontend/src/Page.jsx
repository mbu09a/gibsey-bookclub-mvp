import React from 'react';

// Page is now more presentational regarding the save action
export default function Page({ pageData, onSavePage, isSaved, isSaving, saveError }) {
  if (!pageData) {
    return <p style={{ textAlign: 'center', padding: '20px' }}>Loading page content...</p>;
  }

  return (
    <article className="prose dark:prose-invert max-w-2xl mx-auto p-4 my-6 border rounded shadow-lg bg-white dark:bg-gray-800">
      <div className="flex justify-between items-start mb-3">
        <h2 className="text-2xl font-bold text-gray-800 dark:text-gray-100 flex-grow">{pageData.title}</h2>
        <button 
          onClick={onSavePage}
          disabled={isSaved || isSaving}
          className={`ml-4 px-3 py-1.5 border rounded-md text-sm font-medium transition-colors 
                      ${isSaved 
                        ? 'bg-gray-200 text-gray-500 cursor-not-allowed dark:bg-gray-700 dark:text-gray-400' 
                        : 'bg-teal-500 hover:bg-teal-600 text-white dark:bg-teal-600 dark:hover:bg-teal-700'}
                      ${isSaving ? 'opacity-70 cursor-wait' : ''}`}
        >
          {isSaving ? 'Saving...' : (isSaved ? '✓ Saved' : '💾 Save')}
        </button>
      </div>
      {saveError && !isSaved && <p className="text-xs text-red-500 mb-2 -mt-2 text-right">Error: {saveError}</p>}
      <p className="whitespace-pre-wrap leading-relaxed text-gray-700 dark:text-gray-200">{pageData.text}</p>
    </article>
  );
} 