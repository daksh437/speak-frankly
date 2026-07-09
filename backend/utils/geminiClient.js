/**
 * Thin Gemini REST client (adapted from InstaFlow's geminiClient).
 * - runGemini(prompt, opts): single-turn or system+user text generation.
 * - runGeminiChat(messages, opts): multi-turn conversation for the tutor.
 * Without GEMINI_API_KEY, callers should fall back to MOCK replies (see tutorController).
 */
const axios = require('axios');

const apiKey = process.env.GEMINI_API_KEY;
const MODEL = (process.env.GEMINI_MODEL && process.env.GEMINI_MODEL.trim()) || 'gemini-3-flash-preview';

if (!apiKey || apiKey.trim() === '') {
  console.warn('[GeminiClient] ⚠️ GEMINI_API_KEY not set — running in MOCK mode.');
}

function hasKey() {
  return !!(apiKey && apiKey.trim() !== '');
}

function buildUrl(modelName) {
  const base = 'https://generativelanguage.googleapis.com';
  const version = modelName === 'gemini-pro' ? 'v1' : 'v1beta';
  return `${base}/${version}/models/${modelName}:generateContent?key=${apiKey}`;
}

async function postToGemini(contents, opts = {}, systemInstruction) {
  if (!hasKey()) throw new Error('GEMINI_API_UNAVAILABLE: GEMINI_API_KEY not set');

  const requestBody = {
    contents,
    generationConfig: {
      temperature: opts.temperature ?? 0.8,
      maxOutputTokens: opts.maxTokens ?? 1024,
      topP: opts.topP ?? 0.95,
      topK: opts.topK ?? 40,
    },
  };
  if (systemInstruction) {
    requestBody.systemInstruction = { parts: [{ text: systemInstruction }] };
  }

  try {
    const response = await axios.post(buildUrl(MODEL), requestBody, {
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      timeout: opts.timeout ?? 30000,
      validateStatus: (s) => s < 500,
    });

    if (response.status >= 400) {
      const message = response.data?.error?.message || `HTTP ${response.status}`;
      if (response.status === 404) throw new Error(`GEMINI_MODEL_NOT_FOUND: ${MODEL}`);
      if (response.status === 403) throw new Error('GEMINI_PERMISSION_DENIED');
      throw new Error(`GEMINI_API_ERROR: ${message}`);
    }

    const parts = response.data?.candidates?.[0]?.content?.parts;
    if (Array.isArray(parts)) {
      const text = parts.map((p) => p?.text || '').join('').trim();
      if (text) return text;
    }
    throw new Error('GEMINI_EMPTY_RESPONSE');
  } catch (error) {
    if (error.code === 'ECONNABORTED' || /timeout/i.test(error.message)) {
      throw new Error('GEMINI_TIMEOUT');
    }
    throw error;
  }
}

/** Single prompt (optionally with a system instruction). Returns plain text. */
async function runGemini(prompt, opts = {}) {
  const text = (prompt || opts.userPrompt || '').trim();
  if (!text) throw new Error('Prompt cannot be empty');
  const contents = [{ role: 'user', parts: [{ text }] }];
  return postToGemini(contents, opts, opts.systemPrompt);
}

/**
 * Multi-turn chat for the tutor.
 * @param {Array<{role:'user'|'model', text:string}>} messages
 * @param {object} opts - { systemPrompt, temperature, maxTokens }
 */
async function runGeminiChat(messages, opts = {}) {
  const contents = (messages || [])
    .filter((m) => m && typeof m.text === 'string' && m.text.trim())
    .map((m) => ({
      role: m.role === 'model' || m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.text.trim() }],
    }));
  if (contents.length === 0) throw new Error('No chat messages provided');
  return postToGemini(contents, opts, opts.systemPrompt);
}

module.exports = { runGemini, runGeminiChat, hasKey, MODEL };
