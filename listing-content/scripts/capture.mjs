/**
 * Pull a raw screenshot off the connected phone into screenshots/raw/.
 *
 * Real device, not the emulator: the emulator has no signed-in account, so
 * every screen behind AuthGate would be empty — no streak, no saved words, no
 * conversation history. Screenshots of an empty app sell an empty app.
 *
 * Usage:
 *   node scripts/capture.mjs                 # list devices and the shot list
 *   node scripts/capture.mjs 01-chat         # capture whatever is on screen now
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RAW = resolve(ROOT, 'screenshots/raw');

const ADB_CANDIDATES = [
  `${process.env.LOCALAPPDATA || ''}/Android/sdk/platform-tools/adb.exe`,
  `${process.env.USERPROFILE || ''}/AppData/Local/Android/sdk/platform-tools/adb.exe`,
  `${process.env.ANDROID_HOME || ''}/platform-tools/adb.exe`,
  `${process.env.HOME || ''}/Library/Android/sdk/platform-tools/adb`,
  '/usr/bin/adb',
];

function findAdb() {
  const found = ADB_CANDIDATES.find((p) => p && existsSync(p));
  if (!found) throw new Error('adb not found — set ANDROID_HOME or install platform-tools.');
  return found;
}

function devices(adb) {
  const out = execFileSync(adb, ['devices'], { encoding: 'utf8' });
  return out
    .split('\n')
    .slice(1)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('*'))
    .map((l) => {
      const [id, state] = l.split(/\s+/);
      return { id, state };
    });
}

/** The eight shots, in the order they'll appear on the Play listing. */
const SHOTS = [
  ['01-chat', 'A scenario conversation showing a correction card'],
  ['02-scenarios', 'Home / scenario library'],
  ['03-suggestions', 'Chat with the tap-to-reply chips visible'],
  ['04-speaking', 'Speaking practice with a pronunciation score'],
  ['05-dictionary', 'A tutor line with the dictionary sheet open on a word'],
  ['06-review', 'Saved words / spaced-repetition review'],
  ['07-game', 'Picture match or word guess mid-round'],
  ['08-progress', 'Profile or session report with streak + XP'],
];

const adb = findAdb();
const name = process.argv[2];

if (!name) {
  const list = devices(adb);
  console.log('Devices:');
  if (!list.length) console.log('  (none — plug the phone in and enable USB debugging)');
  list.forEach((d) => console.log(`  ${d.id}  ${d.state}`));
  console.log('\nShot list — navigate to each screen, then run the command:');
  SHOTS.forEach(([id, what]) => {
    const done = existsSync(resolve(RAW, `${id}.png`)) ? '✅' : '  ';
    console.log(`  ${done} node scripts/capture.mjs ${id.padEnd(16)} ${what}`);
  });
  process.exit(0);
}

const ready = devices(adb).filter((d) => d.state === 'device');
if (!ready.length) {
  console.error('No phone ready. Plug it in, enable USB debugging, and accept the prompt on the phone.');
  process.exit(1);
}

mkdirSync(RAW, { recursive: true });
const out = resolve(RAW, `${name}.png`);

// exec-out keeps the PNG bytes binary-clean; plain `shell screencap` mangles
// them with CRLF translation on Windows and yields a corrupt file.
const png = execFileSync(adb, ['exec-out', 'screencap', '-p'], { maxBuffer: 64 * 1024 * 1024 });
writeFileSync(out, png);

const b = readFileSync(out);
if (b.slice(1, 4).toString() !== 'PNG') {
  console.error(`Captured file is not a valid PNG (${b.length} bytes) — try again.`);
  process.exit(1);
}
console.log(`✅ ${name}.png  ${b.readUInt32BE(16)}x${b.readUInt32BE(20)}  (${Math.round(b.length / 1024)} KB)`);
