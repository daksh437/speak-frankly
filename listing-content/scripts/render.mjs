/**
 * HTML → PNG at exact pixel dimensions, using the Chrome already on this
 * machine. No npm dependency, no design tool, no browser automation library.
 *
 * Play rejects assets that are even one pixel off the required size, so every
 * render is measured from the PNG's own IHDR header afterwards and the script
 * fails loudly rather than handing back something that looks fine but uploads
 * as an error.
 *
 * Usage:
 *   node scripts/render.mjs              # everything in the manifest
 *   node scripts/render.mjs feature      # one target by name
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const CHROME_CANDIDATES = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  `${process.env.LOCALAPPDATA || ''}/Google/Chrome/Application/chrome.exe`,
  '/usr/bin/google-chrome',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
];

function findChrome() {
  const found = CHROME_CANDIDATES.find((p) => p && existsSync(p));
  if (!found) {
    throw new Error('Chrome not found. Install it, or add its path to CHROME_CANDIDATES.');
  }
  return found;
}

/** Read a PNG's real dimensions straight out of the IHDR chunk. */
function pngSize(file) {
  const b = readFileSync(file);
  if (b.slice(1, 4).toString() !== 'PNG') throw new Error(`${file} is not a PNG`);
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

/**
 * Play's phone screenshots are uploaded at 2x for a crisp result, while the
 * feature graphic and icon must be EXACTLY 1024x500 and 512x512. So scale is
 * per-target rather than global.
 */
function render(chrome, { html, out, w, h, scale = 1 }) {
  const htmlPath = resolve(ROOT, html);
  const outPath = resolve(ROOT, out);
  if (!existsSync(htmlPath)) throw new Error(`missing source: ${htmlPath}`);
  mkdirSync(dirname(outPath), { recursive: true });

  execFileSync(
    chrome,
    [
      '--headless',
      '--disable-gpu',
      '--hide-scrollbars',
      '--default-background-color=00000000',
      `--force-device-scale-factor=${scale}`,
      `--window-size=${w},${h}`,
      `--screenshot=${outPath.replace(/\//g, '\\')}`,
      `file:///${htmlPath.replace(/\\/g, '/')}`,
    ],
    { stdio: 'pipe' },
  );

  const got = pngSize(outPath);
  const want = { w: w * scale, h: h * scale };
  if (got.w !== want.w || got.h !== want.h) {
    throw new Error(`${out}: rendered ${got.w}x${got.h}, expected ${want.w}x${want.h}`);
  }
  console.log(`  ✅ ${out.padEnd(44)} ${got.w}x${got.h}`);
}

// Play Console's required sizes. Screenshots are added by build-screenshots.mjs.
// The ICON is deliberately absent: the app already ships a finished 512x512
// launcher icon (app/assets/icon_512.png) and the brief is explicit that an
// existing icon must be reused, not redesigned. It is copied byte-for-byte to
// icon/icon-512.png instead of being rendered here.
const MANIFEST = {
  feature: { html: 'graphics/src/feature.html', out: 'graphics/feature-graphic-1024x500.png', w: 1024, h: 500 },
  featureAlt: { html: 'graphics/src/feature-alt.html', out: 'graphics/feature-graphic-alternative.png', w: 1024, h: 500 },
};

const only = process.argv[2];
const targets = only ? { [only]: MANIFEST[only] } : MANIFEST;
if (only && !MANIFEST[only]) {
  console.error(`Unknown target "${only}". Known: ${Object.keys(MANIFEST).join(', ')}`);
  process.exit(1);
}

const chrome = findChrome();
console.log(`Rendering with ${chrome}\n`);
let failed = 0;
for (const [name, spec] of Object.entries(targets)) {
  try {
    render(chrome, spec);
  } catch (e) {
    console.error(`  ❌ ${name}: ${e.message}`);
    failed++;
  }
}
process.exit(failed ? 1 : 0);
