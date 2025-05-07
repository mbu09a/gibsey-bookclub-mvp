import React from 'react';
import { useCredits } from './hooks/useCredits';

// CreditsBadge presentational component
export default function CreditsBadge({ credits }) {
  if (credits === null || typeof credits === 'undefined') {
    return null; 
  }
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