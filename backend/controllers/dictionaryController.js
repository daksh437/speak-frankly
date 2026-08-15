/**
 * Dictionary card endpoint. The card itself (dictionaryapi.dev) is fast, free
 * and cached, so it stays public.
 *
 * The optional `?target=<language>` translation is NOT free — it's a Gemini
 * call. It used to run for any anonymous caller, which meant a loop over random
 * words could burn the whole AI quota. Now it requires a signed-in learner with
 * aux budget left, and translations are cached across users (vocabulary repeats
 * heavily, so most lookups never reach Gemini). Failure is always graceful:
 * the card comes back with `translation: null` rather than an error.
 */
const { lookup } = require('../services/dictionaryService');
const { runGemini, hasKey } = require('../utils/geminiClient');
const { getAuxAccess, recordAuxUsage } = require('../middleware/aiAccess');

const T_CACHE = new Map(); // `${word}|${target}` -> { text, ts }
const T_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const T_MAX = 5000;

function cachedTranslation(key) {
  const hit = T_CACHE.get(key);
  if (!hit) return null;
  if (Date.now() - hit.ts > T_TTL_MS) {
    T_CACHE.delete(key);
    return null;
  }
  return hit.text;
}

function cacheTranslation(key, text) {
  if (T_CACHE.size >= T_MAX) {
    const oldest = T_CACHE.keys().next().value;
    if (oldest) T_CACHE.delete(oldest);
  }
  T_CACHE.set(key, { text, ts: Date.now() });
}

async function translateMeaning(word, definition, target) {
  if (!hasKey() || !target || !definition) return null;
  try {
    const prompt = `Translate the English word "${word}" and this short meaning into ${target}. Return ONLY the translation of the word followed by " — " and the translated meaning, nothing else.\nMeaning: ${definition}`;
    const out = await runGemini(prompt, { temperature: 0.2, maxTokens: 120 });
    return String(out || '').trim() || null;
  } catch (_) {
    return null;
  }
}

/** GET /dictionary/:word?target=Hindi */
async function define(req, res) {
  const word = req.params.word;
  const target = (req.query.target || '').toString().trim().slice(0, 40);

  const card = await lookup(word);
  if (!card) {
    return res.status(404).json({ success: false, error: 'WORD_NOT_FOUND', message: `No dictionary entry for "${word}".` });
  }

  const primary = card.meanings && card.meanings[0] ? card.meanings[0].definition : '';
  let translation = null;

  if (target && primary) {
    const key = `${card.word.toLowerCase()}|${target.toLowerCase()}`;
    translation = cachedTranslation(key);
    if (translation === null && req.uid) {
      // Only a real (uncached) Gemini call costs budget.
      const access = await getAuxAccess(req.uid, (req.headers['x-device-id'] || '').toString().trim());
      if (access.allowed) {
        translation = await translateMeaning(card.word, primary, target);
        if (translation) {
          cacheTranslation(key, translation);
          recordAuxUsage(req.uid).catch(() => {});
        }
      }
    }
  }

  return res.json({ success: true, data: { ...card, translation } });
}

module.exports = { define };
