import React from 'react';

export default function Page({ pageData }) {
  if (!pageData) {
    return <p style={{ textAlign: 'center', padding: '20px' }}>Loading page content...</p>;
  }

  return (
    <article className="prose dark:prose-invert max-w-2xl mx-auto p-4 my-6 border rounded shadow-lg bg-white">
      <h2 className="text-2xl font-bold mb-3 text-gray-800">{pageData.title}</h2>
      <p className="whitespace-pre-wrap leading-relaxed text-gray-700">{pageData.text}</p>
      {/* Later we might add a save button here as per Day 5 */}
    </article>
  );
} 