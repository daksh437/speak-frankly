/**
 * Compose the Play Store screenshots from real device captures.
 *
 * Each output is a brand-coloured card carrying one headline and one untouched
 * screenshot of the actual app. The screenshot is never redrawn, restyled or
 * recoloured — it is the raw PNG pulled off the phone, cropped only to remove
 * the status bar and the bottom strip (which can carry an ad banner), so that
 * every shot shares one identical viewport.
 *
 * Colours come from the app's own launcher icon, sampled pixel-for-pixel.
 *
 * TWO VARIANTS, ONE SET OF CAPTURES:
 *   phone   1080x1920 (9:16)  — the required set
 *   tablet  1920x1080 (16:9)  — satisfies the 7-inch spec (sides 320-3840),
 *                               the 10-inch spec (sides 1080-7680) and the
 *                               Chromebook spec, so one file serves all three.
 *
 * The app has no tablet-specific layout, so a "tablet screenshot" shows phone
 * UI whatever we do. Rather than stretch the capture, the landscape canvas
 * gives the headline room beside the device — which is what large-screen
 * listings actually look like.
 *
 * Usage: node scripts/build-screenshots.mjs
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, unlinkSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RAW = resolve(ROOT, 'screenshots/raw');
const TMP = resolve(ROOT, 'screenshots/src/.build');

const VARIANTS = {
  phone: { w: 1080, h: 1920, dir: 'screenshots', landscape: false },
  tablet: { w: 1920, h: 1080, dir: 'screenshots/tablet', landscape: true },
};

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
const CROP_H = CROP_BOTTOM - CROP_TOP;

const BEZEL = 14;

function buildHtml(shot, V, srcW, srcH, dataUri) {
  const { w: W, h: H, landscape } = V;

  // Portrait sizes the device by width so it nearly fills the card below the
  // headline. Landscape sizes it by height so it fits the shorter axis.
  const screenW = landscape
    ? Math.round((H - 190) * (srcW / CROP_H))
    : 864;

  const scale = screenW / srcW;
  const screenH = Math.round(CROP_H * scale);
  const imgH = Math.round(srcH * scale);
  const offsetY = Math.round(CROP_TOP * scale);

  const copyCss = landscape
    ? `left:104px;top:50%;transform:translateY(-50%);width:${Math.round(W * 0.44)}px;text-align:left`
    : 'left:72px;right:72px;top:104px;text-align:center';

  const phoneCss = landscape
    ? 'right:132px;top:50%;transform:translateY(-50%)'
    : 'left:50%;transform:translateX(-50%);top:430px';

  const h1Size = landscape ? 68 : 62;

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
  .orb2{width:360px;height:360px;left:-160px;bottom:-120px;opacity:.05}

  .copy{position:absolute;${copyCss}}
  h1{margin:0;color:#fff;font-size:${h1Size}px;line-height:1.1;font-weight:800;
     letter-spacing:-1.4px}
  p{margin:22px 0 0;color:#E4DEFF;font-size:30px;line-height:1.35;font-weight:400}

  /* The device. Nothing here touches the screenshot's own pixels. */
  .phone{position:absolute;${phoneCss};width:${screenW + BEZEL * 2}px;
    background:#14111c;border-radius:${BEZEL * 3}px;padding:${BEZEL}px;
    box-shadow:0 30px 70px rgba(26,16,74,.45)}
  .screen{width:${screenW}px;height:${screenH}px;overflow:hidden;
    border-radius:${BEZEL * 2}px;background:#F7F6FC;position:relative}
  .screen img{position:absolute;left:0;top:${-offsetY}px;
    width:${screenW}px;height:${imgH}px;display:block}
</style></head>
<body>
  <div class="card">
    <div class="orb orb1"></div>
    <div class="orb orb2"></div>
    <div class="copy">
      <h1>${shot.headline}</h1>
      <p>${shot.support}</p>
    </div>
    <div class="phone"><div class="screen"><img src="${dataUri}" alt=""></div></div>
  </div>
</body></html>`;
}

mkdirSync(TMP, { recursive: true });

let failed = 0;

for (const [name, V] of Object.entries(VARIANTS)) {
  const outDir = resolve(ROOT, V.dir);
  mkdirSync(outDir, { recursive: true });
  console.log(`\n${name.toUpperCase()}  ${V.w}x${V.h}  → ${V.dir}/`);

  for (const shot of cfg.shots) {
    const src = resolve(RAW, shot.source);
    try {
      if (!existsSync(src)) throw new Error(`missing capture: raw/${shot.source}`);
      const { w: srcW, h: srcH } = pngSize(src);
      const dataUri = `data:image/png;base64,${readFileSync(src).toString('base64')}`;

      const htmlPath = resolve(TMP, `${name}-${shot.out}.html`);
      writeFileSync(htmlPath, buildHtml(shot, V, srcW, srcH, dataUri));

      const outPath = resolve(outDir, shot.out);
      execFileSync(
        CHROME,
        [
          '--headless', '--disable-gpu', '--hide-scrollbars',
          '--force-device-scale-factor=1',
          `--window-size=${V.w},${V.h}`,
          `--screenshot=${outPath.replace(/\//g, '\\')}`,
          `file:///${htmlPath.replace(/\\/g, '/')}`,
        ],
        { stdio: 'pipe' },
      );

      const got = pngSize(outPath);
      if (got.w !== V.w || got.h !== V.h) throw new Error(`rendered ${got.w}x${got.h}`);
      unlinkSync(htmlPath);
      console.log(`  ✅ ${shot.out.padEnd(26)} ${got.w}x${got.h}`);
    } catch (e) {
      console.error(`  ❌ ${shot.out}: ${e.message}`);
      failed++;
    }
  }
}

process.exit(failed ? 1 : 0);
