/**
 * The tutor: a friendly conversation partner (not a strict teacher).
 * - Mirrors the learner's level (simple in → simple out).
 * - Answers the MEANING first, then adds at most 1–2 gentle corrections.
 * - Returns structured JSON so the app can render the reply, tap-to-fix
 *   corrections, quick-reply suggestions, and an optional L1 translation.
 *
 * Runs in MOCK mode (canned but sensible replies) when GEMINI_API_KEY is unset,
 * so the whole app is usable before AI is wired.
 */
const { runGeminiChat, hasKey } = require('../utils/geminiClient');
const { recordAiUsage } = require('../middleware/aiAccess');
const { getScenario } = require('../services/scenarioData');

function extractJson(text) {
  if (!text || typeof text !== 'string') return null;
  const cleaned = text.replace(/```(?:json)?/g, '').trim();
  try {
    return JSON.parse(cleaned);
  } catch (_) {
    const a = cleaned.indexOf('{');
    const b = cleaned.lastIndexOf('}');
    if (a !== -1 && b > a) {
      try { return JSON.parse(cleaned.slice(a, b + 1)); } catch (_) { /* fall through */ }
    }
    return null;
  }
}

function buildSystemPrompt(scenario, level, nativeLanguage) {
  const role = scenario
    ? scenario.setup
    : 'You are a warm, encouraging English conversation partner having a casual chat.';
  const goals = scenario && scenario.goals ? `\nScenario goals for the learner: ${scenario.goals.join('; ')}.` : '';

  return `${role}${goals}

You are helping someone learn English by talking with them in a real-life situation.
The learner's approximate level is ${level || 'A2'} (CEFR). Their native language is ${nativeLanguage || 'unknown'}.

RULES:
- Stay fully in character for the scenario. Keep the conversation moving naturally.
- MATCH the learner's level: at A0–A2 use short, simple sentences and common words. At B1+ you may use richer language.
- Respond to the MEANING of what they said, even if their grammar is wrong. Never lecture.
- Point out at most 1–2 of the most useful corrections per turn (skip tiny errors).
- Be kind and encouraging. One short natural reply, not a paragraph.

Return ONLY valid JSON (no markdown) in exactly this shape:
{
  "reply": "your in-character reply (1–3 short sentences)",
  "corrections": [
    { "original": "what they wrote", "better": "the corrected version", "reason": "very short, simple why" }
  ],
  "suggestions": ["a short reply the learner could say next", "another option"],
  "translation": null
}
- "corrections": [] if their message was fine.
- "suggestions": 2 short phrases the learner could use to continue, at their level.
- "translation": always null (the app handles translation separately).`;
}

// ---- MOCK mode (no API key) ------------------------------------------------
function mockReply(scenario, userText) {
  const text = String(userText || '').trim();
  const base = scenario ? `Nice! ${scenario.title} practice is going well.` : 'Nice, tell me more!';
  return {
    reply: text ? `${base} You said: "${text.slice(0, 60)}". What happens next?` : (scenario?.starter || 'Hi! Shall we begin?'),
    corrections: [],
    suggestions: scenario && scenario.keywords ? scenario.keywords.slice(0, 2).map((k) => `Something about ${k}`) : ['Okay.', 'Can you help me?'],
    translation: null,
    mock: true,
  };
}

/**
 * POST /tutor/chat
 * body: { scenarioId?, level?, nativeLanguage?, messages: [{role:'user'|'model', text}] }
 */
async function chat(req, res) {
  const body = req.body || {};
  const scenario = body.scenarioId ? getScenario(body.scenarioId) : null;
  const level = body.level;
  const nativeLanguage = body.nativeLanguage;
  const messages = Array.isArray(body.messages) ? body.messages : [];

  const lastUser = [...messages].reverse().find((m) => (m.role || 'user') === 'user');

  if (!hasKey()) {
    // MOCK mode: still record usage so limit behavior can be tested end-to-end.
    if (req.uid) recordAiUsage(req.uid).catch(() => {});
    return mockReply(scenario, lastUser && lastUser.text);
  }

  const systemPrompt = buildSystemPrompt(scenario, level, nativeLanguage);
  const chatMessages = messages.length > 0
    ? messages
    : [{ role: 'user', text: 'Hello!' }];

  const raw = await runGeminiChat(chatMessages, { systemPrompt, temperature: 0.8, maxTokens: 700 });
  const parsed = extractJson(raw);

  // If the model didn't return JSON, treat the whole text as the reply.
  const result = parsed && typeof parsed === 'object'
    ? {
        reply: String(parsed.reply || '').trim() || 'Okay!',
        corrections: Array.isArray(parsed.corrections) ? parsed.corrections.slice(0, 2) : [],
        suggestions: Array.isArray(parsed.suggestions) ? parsed.suggestions.slice(0, 3) : [],
        translation: null,
      }
    : { reply: String(raw || '').trim().slice(0, 500), corrections: [], suggestions: [], translation: null };

  // Only record usage after a confirmed successful reply.
  if (req.uid) recordAiUsage(req.uid).catch(() => {});
  return result;
}

/**
 * POST /tutor/feedback
 * body: { scenarioId?, level?, messages: [...] }
 * Returns a short end-of-session report.
 */
async function feedback(req, res) {
  const body = req.body || {};
  const scenario = body.scenarioId ? getScenario(body.scenarioId) : null;
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const learnerTurns = messages.filter((m) => (m.role || 'user') === 'user').map((m) => m.text).join('\n');

  if (!hasKey() || !learnerTurns.trim()) {
    return {
      phrases_learned: scenario ? scenario.keywords.slice(0, 4) : ['hello', 'thank you'],
      grammar_notes: [],
      encouragement: 'Good session! A little practice every day adds up fast. 🌟',
      mock: !hasKey(),
    };
  }

  const prompt = `A learner just finished an English conversation practice${scenario ? ` (scenario: ${scenario.title})` : ''}.
Here is everything the learner said:
"""
${learnerTurns}
"""

Write a short, encouraging feedback report. Return ONLY valid JSON:
{
  "phrases_learned": ["3-5 useful words or phrases they used or should remember"],
  "grammar_notes": [ { "point": "one pattern they used or misused", "tip": "a simple fix" } ],
  "encouragement": "one warm sentence"
}
Keep it simple and positive. Max 2 grammar_notes.`;

  const raw = await runGeminiChat([{ role: 'user', text: prompt }], { temperature: 0.5, maxTokens: 600 });
  const parsed = extractJson(raw) || {};
  return {
    phrases_learned: Array.isArray(parsed.phrases_learned) ? parsed.phrases_learned.slice(0, 5) : [],
    grammar_notes: Array.isArray(parsed.grammar_notes) ? parsed.grammar_notes.slice(0, 2) : [],
    encouragement: String(parsed.encouragement || 'Great effort — keep going!').trim(),
  };
}

module.exports = { chat, feedback };
