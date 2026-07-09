/**
 * Dictionary lookup via the Free Dictionary API (https://dictionaryapi.dev),
 * with an in-memory LRU-ish cache to cut latency and rate-limit pressure.
 * Returns a compact card the app can render: meaning, part of speech, example,
 * phonetic + audio, synonyms. Translation to the learner's L1 is handled
 * separately (Gemini) so this stays fast and free.
 */
const axios = require('axios');

const CACHE = new Map(); // word(lowercased) -> { card, ts }
const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24h
const CACHE_MAX = 2000;

function fromCache(word) {
  const hit = CACHE.get(word);
  if (!hit) return null;
  if (Date.now() - hit.ts > CACHE_TTL_MS) {
    CACHE.delete(word);
    return null;
  }
  return hit.card;
}

function toCache(word, card) {
  if (CACHE.size >= CACHE_MAX) {
    const oldest = CACHE.keys().next().value;
    if (oldest) CACHE.delete(oldest);
  }
  CACHE.set(word, { card, ts: Date.now() });
}

/** Shape the noisy API response into a small, predictable card. */
function shapeCard(word, raw) {
  const entry = Array.isArray(raw) ? raw[0] : raw;
  if (!entry) return null;

  const phonetics = Array.isArray(entry.phonetics) ? entry.phonetics : [];
  const audio = (phonetics.find((p) => p.audio && p.audio.trim()) || {}).audio || null;
  const phonetic = entry.phonetic || (phonetics.find((p) => p.text) || {}).text || null;

  const meanings = (Array.isArray(entry.meanings) ? entry.meanings : []).slice(0, 3).map((m) => {
    const def = (Array.isArray(m.definitions) ? m.definitions[0] : null) || {};
    return {
      partOfSpeech: m.partOfSpeech || '',
      definition: def.definition || '',
      example: def.example || '',
      synonyms: (m.synonyms || []).slice(0, 5),
    };
  });

  return {
    word: entry.word || word,
    phonetic,
    audio,
    meanings,
    source: 'dictionaryapi.dev',
  };
}

/** Look up a single word. Returns a card or null if not found. */
async function lookup(rawWord) {
  const word = String(rawWord || '').trim().toLowerCase();
  if (!word || word.length > 60) return null;

  const cached = fromCache(word);
  if (cached) return cached;

  try {
    const url = `https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`;
    const res = await axios.get(url, { timeout: 8000, validateStatus: (s) => s < 500 });
    if (res.status === 404) return null;
    const card = shapeCard(word, res.data);
    if (card) toCache(word, card);
    return card;
  } catch (e) {
    console.warn('[dictionary] lookup error for', word, '-', e.message);
    return null;
  }
}

module.exports = { lookup };
