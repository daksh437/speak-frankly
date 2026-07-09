/**
 * Dictionary card endpoint. Fast, free, cached (dictionaryService). Optionally
 * appends a one-line translation of the primary meaning into the learner's L1
 * via Gemini when ?target=<language> is provided and a key is configured.
 */
const { lookup } = require('../services/dictionaryService');
const { runGemini, hasKey } = require('../utils/geminiClient');

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
  const target = (req.query.target || '').toString().trim();

  const card = await lookup(word);
  if (!card) {
    return res.status(404).json({ success: false, error: 'WORD_NOT_FOUND', message: `No dictionary entry for "${word}".` });
  }

  const primary = card.meanings && card.meanings[0] ? card.meanings[0].definition : '';
  const translation = await translateMeaning(card.word, primary, target);

  return res.json({ success: true, data: { ...card, translation } });
}

module.exports = { define };
