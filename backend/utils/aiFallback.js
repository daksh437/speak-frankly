/**
 * Graceful fallbacks for AI endpoints. When Gemini fails or is unavailable, we
 * return a usable (if generic) payload so the app degrades instead of breaking.
 * The tutor should NEVER show a hard error to a learner mid-conversation.
 */
function buildAiFallback(endpoint = '', body = {}) {
  const path = String(endpoint || '');

  if (path.includes('/tutor/chat')) {
    return {
      reply: "Sorry, I didn't catch that — could you say it again? 🙂",
      corrections: [],
      suggestions: ['Yes, sure.', 'Can you repeat that?'],
      translation: null,
    };
  }

  if (path.includes('/tutor/feedback')) {
    return {
      phrases_learned: [],
      grammar_notes: [],
      encouragement: 'Great effort today — keep practicing a little every day!',
    };
  }

  // Generic default
  return { message: 'Service is busy right now. Please try again.' };
}

module.exports = { buildAiFallback };
