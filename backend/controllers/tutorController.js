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

  // Custom (context-generated) scenarios send their setup as `context` since the
  // server can't look them up by id.
  const customContext = typeof body.context === 'string' ? body.context.trim() : '';
  const effectiveScenario = scenario
    || (customContext ? { setup: customContext, goals: [], title: 'Chat', keywords: [], starter: '' } : null);

  const lastUser = [...messages].reverse().find((m) => (m.role || 'user') === 'user');

  if (!hasKey()) {
    // MOCK mode: still record usage so limit behavior can be tested end-to-end.
    if (req.uid) recordAiUsage(req.uid).catch(() => {});
    return mockReply(effectiveScenario, lastUser && lastUser.text);
  }

  const systemPrompt = buildSystemPrompt(effectiveScenario, level, nativeLanguage);
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

const FALLBACK_SPEAKING_PHRASES = [
  'Good morning! How are you today?',
  'Nice to meet you.',
  'Could you help me, please?',
  'I would like a cup of coffee.',
  'How much does this cost?',
  'Where is the train station?',
  'Can you repeat that, please?',
  'I have been learning English for a month.',
  'What time does the meeting start?',
  'Thank you very much for your help.',
  'I am looking for a new job.',
  'I really enjoyed the movie.',
];

function extractJsonArray(text) {
  if (!text || typeof text !== 'string') return null;
  const cleaned = text.replace(/```(?:json)?/g, '').trim();
  try {
    const v = JSON.parse(cleaned);
    if (Array.isArray(v)) return v;
  } catch (_) {/* fall through */}
  const a = cleaned.indexOf('[');
  const b = cleaned.lastIndexOf(']');
  if (a !== -1 && b > a) {
    try {
      const v = JSON.parse(cleaned.slice(a, b + 1));
      if (Array.isArray(v)) return v;
    } catch (_) {/* fall through */}
  }
  return null;
}

/**
 * POST /speaking/phrases -> { phrases: string[] }
 * Level/goal-aware phrases for listen-and-imitate practice. Not metered (the
 * client caches one set per day). Always returns usable phrases (fallback).
 */
async function speakingPhrases(req) {
  const body = req.body || {};
  const level = (body.level || 'A2').toString();
  const goal = (body.goal || 'everyday conversation').toString();
  const count = Math.min(Math.max(parseInt(body.count, 10) || 12, 4), 20);

  if (!hasKey()) return { phrases: FALLBACK_SPEAKING_PHRASES.slice(0, count), mock: true };

  const seed = Date.now() + Math.floor(Math.random() * 100000);
  const prompt = `Generate ${count} short, natural spoken English phrases for a learner to practice saying aloud.
Learner level: ${level} (CEFR). Learner goal: ${goal}.
Rules:
- Match the level (A0-A2: very simple and short; B1+: natural, slightly longer).
- Make them useful for the learner's goal.
- Everyday, realistic, and varied. Each phrase 4-10 words, normal capitalization and punctuation.
Return ONLY a JSON array of ${count} strings - no numbering, no extra text.
Variety seed: ${seed}`;

  try {
    const raw = await runGeminiChat([{ role: 'user', text: prompt }], { temperature: 0.9, maxTokens: 2000 });
    const arr = extractJsonArray(raw);
    const phrases = Array.isArray(arr)
      ? arr.map((s) => String(s).trim()).filter((s) => s.length > 0 && s.length <= 120).slice(0, count)
      : [];
    if (phrases.length >= 4) return { phrases };
  } catch (e) {
    console.warn('[speakingPhrases] error:', e.message);
  }
  return { phrases: FALLBACK_SPEAKING_PHRASES.slice(0, count), fallback: true };
}

/**
 * POST /custom/scenario -> { scenario } — turn any topic the learner types into
 * a ready-to-chat scenario (title, emoji, opening line, goals, key words, and an
 * internal `setup` the chat endpoint uses as context). Not metered; the chat
 * that follows is metered normally.
 */
function _fallbackCustomScenario(topic, level) {
  return {
    id: 'custom',
    theme: 'custom',
    level,
    title: topic.slice(0, 40) || 'Free chat',
    emoji: '💬',
    description: `Practice talking about ${topic}.`,
    goals: [`Talk about ${topic}`, 'Ask and answer questions'],
    starter: `Sure! Let's talk about ${topic}. What would you like to say?`,
    keywords: [],
    setup: `You are a friendly English conversation partner chatting about "${topic}" with a ${level} learner. Keep it natural and encouraging.`,
  };
}

async function customScenario(req) {
  const body = req.body || {};
  const topic = (body.topic || '').toString().trim().slice(0, 200);
  const level = (body.level || 'A2').toString();
  if (!topic) return { error: 'topic_required' };
  if (!hasKey()) return { scenario: _fallbackCustomScenario(topic, level) };

  const prompt = `Create a short English conversation practice scenario about the topic: "${topic}".
Learner level: ${level} (CEFR).
Return ONLY JSON with these keys:
{
  "title": "short title (max 5 words)",
  "emoji": "one relevant emoji",
  "description": "one short line describing the practice",
  "goals": ["2-3 short learner goals"],
  "starter": "the tutor's friendly opening line, in character, matched to the level",
  "keywords": ["5-7 useful words/phrases for this topic"],
  "setup": "one paragraph telling the AI tutor what role to play and how to run this conversation at level ${level}"
}`;
  try {
    const raw = await runGeminiChat([{ role: 'user', text: prompt }], { temperature: 0.8, maxTokens: 1500 });
    const parsed = extractJson(raw);
    if (parsed && parsed.setup) {
      return {
        scenario: {
          id: 'custom',
          theme: 'custom',
          level,
          title: String(parsed.title || topic).slice(0, 60),
          emoji: String(parsed.emoji || '💬').slice(0, 4),
          description: String(parsed.description || `Talk about ${topic}.`),
          goals: Array.isArray(parsed.goals) ? parsed.goals.map(String).slice(0, 4) : [],
          starter: String(parsed.starter || `Let's talk about ${topic}!`),
          keywords: Array.isArray(parsed.keywords) ? parsed.keywords.map(String).slice(0, 8) : [],
          setup: String(parsed.setup),
        },
      };
    }
  } catch (e) {
    console.warn('[customScenario] error:', e.message);
  }
  return { scenario: _fallbackCustomScenario(topic, level) };
}

module.exports = { chat, feedback, speakingPhrases, customScenario };
