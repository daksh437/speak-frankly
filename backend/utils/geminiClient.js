/**
 * Thin Gemini REST client (adapted from InstaFlow's geminiClient).
 * - runGemini(prompt, opts): single-turn or system+user text generation.
 * - runGeminiChat(messages, opts): multi-turn conversation for the tutor.
 * Without GEMINI_API_KEY, callers should fall back to MOCK replies (see tutorController).
 *
 * MODEL FALLBACK CHAIN: quota on the free tier is per-model and small, so one
 * exhausted model used to take the entire app down — every AI path silently
 * degraded to canned text. We now try each model in GEMINI_MODELS in order and
 * only give up when all of them fail. Counters below are exposed on /health so
 * an outage is visible instead of hiding behind the graceful fallbacks.
 */
const axios = require('axios');

const apiKey = process.env.GEMINI_API_KEY;
const MODEL = (process.env.GEMINI_MODEL && process.env.GEMINI_MODEL.trim()) || 'gemini-3-flash-preview';

// Ordered chain: the configured model first, then progressively older/cheaper
// ones. Override wholesale with GEMINI_MODELS=a,b,c.
const DEFAULT_FALLBACKS = ['gemini-2.5-flash', 'gemini-2.0-flash'];
const MODELS = [
  ...new Set(
    [
      MODEL,
      ...(process.env.GEMINI_MODELS || '').split(',').map((s) => s.trim()).filter(Boolean),
      ...DEFAULT_FALLBACKS,
    ].filter(Boolean),
  ),
];

const stats = { calls: 0, ok: 0, failed: 0, fallbacks: 0, byModel: {}, lastError: null, lastErrorAt: null };

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

/** Worth trying the next model in the chain? (quota, missing model, upstream hiccup) */
function shouldFallOver(err) {
  const m = String(err && err.message ? err.message : err);
  return (
    m.includes('GEMINI_QUOTA') ||
    m.includes('GEMINI_MODEL_NOT_FOUND') ||
    m.includes('GEMINI_PERMISSION_DENIED') ||
    m.includes('GEMINI_UPSTREAM') ||
    m.includes('GEMINI_TIMEOUT') ||
    m.includes('GEMINI_EMPTY_RESPONSE')
  );
}

/** One attempt against one model. Throws a tagged error on failure. */
async function callModel(modelName, contents, opts, systemInstruction) {
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

  let response;
  try {
    response = await axios.post(buildUrl(modelName), requestBody, {
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      timeout: opts.timeout ?? 30000,
      validateStatus: (s) => s < 600,
    });
  } catch (error) {
    if (error.code === 'ECONNABORTED' || /timeout/i.test(error.message)) {
      throw new Error('GEMINI_TIMEOUT');
    }
    throw new Error(`GEMINI_UPSTREAM: ${error.message}`);
  }

  if (response.status >= 400) {
    const message = response.data?.error?.message || `HTTP ${response.status}`;
    if (response.status === 429) throw new Error(`GEMINI_QUOTA: ${modelName}`);
    if (response.status === 404) throw new Error(`GEMINI_MODEL_NOT_FOUND: ${modelName}`);
    if (response.status === 403) throw new Error(`GEMINI_PERMISSION_DENIED: ${modelName}`);
    if (response.status >= 500) throw new Error(`GEMINI_UPSTREAM: ${message}`);
    throw new Error(`GEMINI_API_ERROR: ${message}`);
  }

  const parts = response.data?.candidates?.[0]?.content?.parts;
  if (Array.isArray(parts)) {
    const text = parts.map((p) => p?.text || '').join('').trim();
    if (text) return text;
  }
  throw new Error('GEMINI_EMPTY_RESPONSE');
}

async function postToGemini(contents, opts = {}, systemInstruction) {
  if (!hasKey()) throw new Error('GEMINI_API_UNAVAILABLE: GEMINI_API_KEY not set');

  stats.calls++;
  let lastError;
  for (let i = 0; i < MODELS.length; i++) {
    const modelName = MODELS[i];
    try {
      const text = await callModel(modelName, contents, opts, systemInstruction);
      stats.ok++;
      stats.byModel[modelName] = (stats.byModel[modelName] || 0) + 1;
      if (i > 0) {
        stats.fallbacks++;
        console.warn(`[GeminiClient] served by fallback model ${modelName} (after ${MODELS[i - 1]} failed)`);
      }
      return text;
    } catch (e) {
      lastError = e;
      if (i < MODELS.length - 1 && shouldFallOver(e)) {
        console.warn(`[GeminiClient] ${modelName} failed (${e.message}) — trying ${MODELS[i + 1]}`);
        continue;
      }
      break;
    }
  }

  stats.failed++;
  stats.lastError = String(lastError?.message || lastError);
  stats.lastErrorAt = new Date().toISOString();
  console.error('[GeminiClient] all models failed:', stats.lastError);
  throw lastError;
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

/** Snapshot for /health — how the AI layer is actually doing. */
function getAiStats() {
  return { ...stats, byModel: { ...stats.byModel }, models: MODELS };
}

module.exports = { runGemini, runGeminiChat, hasKey, MODEL, MODELS, getAiStats };
