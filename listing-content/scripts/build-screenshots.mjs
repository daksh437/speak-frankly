/**
 * Compose the eight Play Store screenshots from real device captures.
 *
 * Each output is a brand-coloured card carrying one headline and one untouched
 * screenshot of the actual app. The screenshot is never redrawn, restyled or
 * recoloured — it is the raw PNG pulled off the phone, cropped only to remove
 * the status bar and the bottom strip (which can carry an ad banner), so that
 * all eight share one identical viewport.
 *
 * Colours come from the app's own launcher icon, sampled pixel-for-pixel.
 *
 * Output: 1080x1920 (9:16), 24-bit PNG, which is inside every Play limit —
 * min 320px, max 3840px, long side no more than 2x the short side.
 *
 * Usage: node scripts/build-screenshots.mjs
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, unlinkSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RAW = resolve(ROOT, 'screenshots/raw');
const OUT = resolve(ROOT, 'screenshots');
const TMP = resolve(ROOT, 'screenshots/src/.build');

const W = 1080;
const H = 1920;

const CHROME = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  `${process.env.LOCALAPPDATA || ''}/Google/Chrome/Application/chrome.exe`,
  '/usr/bin/google-chrome',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
].find((p) => p && existsSync(p));

if (!CHROME) throw new Error('Chrome not found.');

const pngSize = (f) => {
  const b = readFileSync(f);
  if (b.slice(1, 4).toString() !== 'PNG') throw new Error(`${f} is not a PNG`);
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
};

const cfg = JSON.parse(readFileSync(resolve(ROOT, 'screenshots/src/captions.json'), 'utf8'));
const { top: CROP_TOP, bottom: CROP_BOTTOM } = cfg.crop;

/** Phone geometry inside the card. The device bleeds off the bottom edge so the
 *  card reads as a product shot rather than a framed picture. */
// Sized so the device very nearly fills the card below the headline: a
// smaller phone left a dead band of flat purple between copy and screen, which
// reads as unfinished at thumbnail size.
const SCREEN_W = 864;      // visible width of the app screenshot
const BEZEL = 14;          // dark frame thickness around it
const PHONE_TOP = 430;     // y of the phone's outer top edge

function buildHtml({ headline, support, dataUri, srcW, srcH }) {
  // Map the source crop window into the on-card screen box.
  const scale = SCREEN_W / srcW;
  const screenH = Math.round((CROP_BOTTOM - CROP_TOP) * scale);
  const imgH = Math.round(srcH * scale);
  const offsetY = Math.round(CROP_TOP * scale);

  return `<!doctype html>
<html><head><meta charset="utf-8"><style>
  html,body{margin:0;padding:0}
  *{box-sizing:border-box}
  .card{width:${W}px;height:${H}px;position:relative;overflow:hidden;
    background:linear-gradient(160deg,#7A67FF 0%,#6B59EB 46%,#5B4BD6 100%);
    font-family:"Segoe UI","Helvetica Neue",Arial,sans-serif}

  /* Faint depth only — these are judged at thumbnail size, where anything
     busier than this becomes noise behind the headline. */
  .orb{position:absolute;border-radius:50%;background:#fff;opacity:.06}
  .orb1{width:520px;height:520px;right:-190px;top:-210px}
  .orb2{width:360px;height:360px;left:-160px;bottom:120px;opacity:.05}

  .copy{position:absolute;left:72px;right:72px;top:104px;text-align:center}
  h1{margin:0;color:#fff;font-size:62px;line-height:1.1;font-weight:800;
     letter-spacing:-1.4px}
  p{margin:22px 0 0;color:#E4DEFF;font-size:30px;line-height:1.35;font-weight:400}

  /* The device. Nothing here touches the screenshot's own pixels. */
  .phone{position:absolute;left:50%;transform:translateX(-50%);
    top:${PHONE_TOP}px;width:${SCREEN_W + BEZEL * 2}px;
    background:#14111c;border-radius:${BEZEL * 3}px;padding:${BEZEL}px;
    box-shadow:0 30px 70px rgba(26,16,74,.45)}
  .screen{width:${SCREEN_W}px;height:${screenH}px;overflow:hidden;
    border-radius:${BEZEL * 2}px;background:#F7F6FC;position:relative}
  .screen img{position:absolute;left:0;top:${-offsetY}px;
    width:${SCREEN_W}px;height:${imgH}px;display:block}
</style></head>
<body>
  <div class="card">
    <div class="orb orb1"></div>
    <div class="orb orb2"></div>
    <div class="copy">
      <h1>${headline}</h1>
      <p>${support}</p>
    </div>
    <div class="phone"><div class="screen"><img src="${dataUri}" alt=""></div></div>
  </div>
</body></html>`;
}

mkdirSync(TMP, { recursive: true });
mkdirSync(OUT, { recursive: true });

let failed = 0;
console.log(`Composing ${cfg.shots.length} screenshots at ${W}x${H}\n`);

for (const shot of cfg.shots) {
  const src = resolve(RAW, shot.source);
  try {
    if (!existsSync(src)) throw new Error(`missing capture: screenshots/raw/${shot.source}`);
    const { w: srcW, h: srcH } = pngSize(src);
    const dataUri = `data:image/png;base64,${readFileSync(src).toString('base64')}`;

    const htmlPath = resolve(TMP, `${shot.out}.html`);
    writeFileSync(htmlPath, buildHtml({ ...shot, dataUri, srcW, srcH }));

    const outPath = resolve(OUT, shot.out);
    execFileSync(
      CHROME,
      [
        '--headless', '--disable-gpu', '--hide-scrollbars',
        '--force-device-scale-factor=1',
        `--window-size=${W},${H}`,
        `--screenshot=${outPath.replace(/\//g, '\\')}`,
        `file:///${htmlPath.replace(/\\/g, '/')}`,
      ],
      { stdio: 'pipe' },
    );

    const got = pngSize(outPath);
    if (got.w !== W || got.h !== H) throw new Error(`rendered ${got.w}x${got.h}`);
    unlinkSync(htmlPath);
    console.log(`  ✅ ${shot.out.padEnd(26)} ${got.w}x${got.h}   ← raw/${shot.source}`);
  } catch (e) {
    console.error(`  ❌ ${shot.out}: ${e.message}`);
    failed++;
  }
}

process.exit(failed ? 1 : 0);
