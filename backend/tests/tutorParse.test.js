/**
 * Regression: a learner must NEVER see raw JSON in a tutor message bubble.
 *
 * Reported on build 1.5.3 (versionCode 23), Job Interview scenario: the model's
 * JSON answer ran past the output budget, came back truncated mid-object, and
 * the old fallback branch put the JSON source straight into `reply`:
 *
 *   { "reply": "That is a great skill for this job! ...", "corrections": [ { "original":
 *
 * These tests drive the parse path directly (no network, no API key), including
 * an exhaustive check over EVERY truncation point of a full response.
 *
 * Usage: node tests/tutorParse.test.js
 */
process.env.DEV_SKIP_LIMITS = 'true';
// Hermetic: no real Firestore, no real Gemini quota (see tutor.smoke.test.js).
process.env.FIREBASE_SERVICE_ACCOUNT_JSON = '';
process.env.GOOGLE_APPLICATION_CREDENTIALS = '';
process.env.GEMINI_API_KEY = '';

const gemini = require('../utils/geminiClient');

// Stub the AI layer BEFORE the controller is required: it destructures these at
// module load, so the controller picks up the stubs.
let stubbedRaw = '';
gemini.hasKey = () => true;
gemini.runGeminiChat = async () => stubbedRaw;

const { buildChatResult, chat } = require('../controllers/tutorController');
const { buildAiFallback } = require('../utils/aiFallback');

let failures = 0;
function check(name, cond) {
  if (cond) {
    console.log(`  ✅ ${name}`);
  } else {
    console.error(`  ❌ ${name}`);
    failures++;
  }
}

/** The property under test: whatever is in the bubble reads as a sentence. */
function isCleanReply(reply) {
  if (typeof reply !== 'string' || reply.trim() === '') return false;
  const t = reply.trim();
  if (t.startsWith('{') || t.startsWith('[')) return false;
  if (/"(?:reply|corrections|suggestions|original|better|reason|translation)"\s*:/.test(t)) return false;
  if (t.includes('```')) return false;
  return true;
}

const FALLBACK = buildAiFallback('/tutor/chat');

// The exact payload seen on the device (cut off mid-`corrections`).
const REPORTED = '{ "reply": "That is a great skill for this job! Do you also work well in a team?", "corrections": [ { "original":';

const FULL = JSON.stringify({
  reply: 'That is a great skill for this job! Do you also work well in a team?',
  corrections: [{ original: 'I has good skill', better: 'I have good skills', reason: 'Use "have" with "I".' }],
  suggestions: ['Yes, I like teamwork.', 'I work well with others.', 'Can you tell me more?'],
  translation: null,
});

console.log('\n🧪 tutor chat: truncated JSON must never reach the learner\n');

// ---- 1. The reported payload ----------------------------------------------
{
  const r = buildChatResult(REPORTED);
  check('reported truncation → no JSON in the bubble', isCleanReply(r.reply));
  check('reported truncation → salvages the finished reply',
    r.reply === 'That is a great skill for this job! Do you also work well in a team?');
  check('reported truncation → corrections/suggestions are arrays',
    Array.isArray(r.corrections) && Array.isArray(r.suggestions));
  check('reported truncation → translation null', r.translation === null);
}

// ---- 2. Every possible truncation point ------------------------------------
{
  let bad = null;
  for (let i = 1; i < FULL.length; i++) {
    const r = buildChatResult(FULL.slice(0, i));
    if (!isCleanReply(r.reply) || !Array.isArray(r.corrections) || !Array.isArray(r.suggestions)) {
      bad = { i, prefix: FULL.slice(0, i), reply: r.reply };
      break;
    }
  }
  if (bad) console.error(`     cut at ${bad.i}: ${JSON.stringify(bad.prefix)}\n     → reply: ${JSON.stringify(bad.reply)}`);
  check(`every truncation point of a full response stays clean (${FULL.length - 1} cuts)`, bad === null);
}

// ---- 3. Truncation inside the reply string itself ---------------------------
{
  const r = buildChatResult('{ "reply": "That is a great sk');
  check('reply cut mid-sentence → friendly fallback, not half a word', r.reply === FALLBACK.reply);
}

// ---- 4. Truncation before the reply key ------------------------------------
{
  const r = buildChatResult('{ "corrections": [ { "original": "I has", "better":');
  check('no reply key at all → friendly fallback', r.reply === FALLBACK.reply);
  check('no reply key at all → fallback offers suggestions', r.suggestions.length > 0);
}

// ---- 5. Markdown-fenced truncation -----------------------------------------
{
  const r = buildChatResult('```json\n{ "reply": "Nice to meet you!", "corrections": [ {');
  check('fenced + truncated → clean bubble', isCleanReply(r.reply));
  check('fenced + truncated → salvages the reply', r.reply === 'Nice to meet you!');
}

// ---- 6. Escaped quotes inside the reply survive salvage ---------------------
{
  const raw = '{ "reply": "Say \\"thank you\\" next time!", "corrections": [ { "original":';
  const r = buildChatResult(raw);
  check('escaped quotes in a salvaged reply are unescaped', r.reply === 'Say "thank you" next time!');
}

// ---- 7. Well-formed JSON is untouched --------------------------------------
{
  const r = buildChatResult(FULL);
  check('valid JSON → reply preserved', r.reply === JSON.parse(FULL).reply);
  check('valid JSON → corrections preserved', r.corrections.length === 1 && r.corrections[0].better === 'I have good skills');
  check('valid JSON → 3 suggestions preserved', r.suggestions.length === 3);
}

// ---- 8. Plain prose (model ignored the schema) still shows ------------------
{
  const r = buildChatResult('That sounds great! What did you study?');
  check('plain prose → shown as the reply', r.reply === 'That sounds great! What did you study?');
}

// ---- 9. Nothing at all -----------------------------------------------------
{
  check('empty response → friendly fallback', buildChatResult('').reply === FALLBACK.reply);
  check('whitespace response → friendly fallback', buildChatResult('   \n ').reply === FALLBACK.reply);
  check('null response → friendly fallback', buildChatResult(null).reply === FALLBACK.reply);
}

// ---- 10. End to end through chat() -----------------------------------------
(async () => {
  const req = {
    body: {
      scenarioId: 'job-interview',
      level: 'A2',
      nativeLanguage: 'Hindi',
      messages: [{ role: 'user', text: 'I has good skill in computer' }],
    },
  };

  stubbedRaw = REPORTED;
  const truncated = await chat(req, {});
  check('chat() with a truncated model response → clean bubble', isCleanReply(truncated.reply));

  stubbedRaw = FULL;
  const ok = await chat(req, {});
  check('chat() with a complete model response → full payload',
    ok.reply === JSON.parse(FULL).reply && ok.suggestions.length === 3);

  console.log(failures === 0 ? '\n✅ tutor parse tests passed\n' : `\n❌ ${failures} check(s) failed\n`);
  process.exit(failures === 0 ? 0 : 1);
})();
