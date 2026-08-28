/**
 * Build the Play Store promo video from real device recordings.
 *
 * Same rules as the screenshots: the app footage is never redrawn or restyled.
 * Each clip is a raw `adb screenrecord` capture, cropped only to drop the status
 * bar and the bottom strip, then placed in the same device frame the
 * screenshots use so the whole listing reads as one piece.
 *
 * Output: 1080x1920 (9:16), H.264, no audio — screenrecord captures none, and
 * unlicensed music is not worth the copyright claim. Captions carry the story,
 * which is how most store videos are watched anyway (muted).
 *
 * Play takes a YouTube URL, not a file, so the result still has to be uploaded
 * to YouTube by hand.
 *
 * Usage: node scripts/build-video.mjs
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RAW = resolve(ROOT, 'video/raw');
const WORK = resolve(ROOT, 'video/.work');
const OUT = resolve(ROOT, 'video');

const W = 1080, H = 1920;

// Same crop window as the screenshots: drop the status bar, and the bottom band
// that can carry an ad banner.
const CROP_TOP = 110, CROP_BOTTOM = 1900;
const SRC_W = 1080, SRC_H = 2340;
const CROP_H = CROP_BOTTOM - CROP_TOP;

// Device frame geometry — identical to build-screenshots.mjs.
const SCREEN_W = 864;
const SCREEN_H = Math.round(CROP_H * (SCREEN_W / SRC_W));   // 1432
const BEZEL = 14;
const PHONE_X = Math.round((W - SCREEN_W) / 2) - BEZEL;      // outer rect
const PHONE_Y = 430 - BEZEL;
const SCREEN_X = PHONE_X + BEZEL;
const SCREEN_Y = PHONE_Y + BEZEL;

const bin = (name) => {
  const p = [
    `${process.env.LOCALAPPDATA || ''}/Microsoft/WinGet/Links/${name}.exe`,
    `/usr/bin/${name}`,
  ].find((x) => x && existsSync(x));
  if (!p) throw new Error(`${name} not found`);
  return p;
};
const FFMPEG = bin('ffmpeg');
const CHROME = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  `${process.env.LOCALAPPDATA || ''}/Google/Chrome/Application/chrome.exe`,
].find((p) => p && existsSync(p));
if (!CHROME) throw new Error('Chrome not found');

/** Scenes, in order. `start`/`dur` are seconds into the raw capture. */
const SCENES = [
  { id: 'intro', card: true, headline: 'Speak Frankly', support: 'Learn English by talking', dur: 2.5 },
  { id: 'home', src: 'c1-home.mp4', start: 1.0, dur: 6.0,
    headline: 'Learn English by talking', support: 'Not by memorising grammar rules' },
  { id: 'chat', src: 'c2-chat.mp4', start: 17.0, dur: 13.0,
    headline: 'Corrections that don\u2019t sting', support: 'It answers what you meant, then shows the fix' },
  { id: 'story', src: 'c3-story.mp4', start: 1.5, dur: 9.0,
    headline: 'Role-plays that work offline', support: 'Pick your reply and the story branches' },
  { id: 'game', src: 'c4-picturematch.mp4', start: 1.0, dur: 7.0,
    headline: 'Practice that isn\u2019t homework', support: 'Quick games between conversations' },
  { id: 'progress', src: 'c5-progress.mp4', start: 0.8, dur: 4.5,
    headline: 'See yourself improving', support: 'Streak, XP and your fluency map' },
  { id: 'outro', card: true, headline: 'Say something today', support: 'Speak Frankly', dur: 3.0 },
];

function cardHtml({ headline, support, card }) {
  const mark = card
    ? `<div class="mark"><img src="head.png" alt=""></div>`
    : '';
  const phone = card
    ? ''
    : `<div class="phone"></div>`;
  return `<!doctype html>
<html><head><meta charset="utf-8"><style>
  html,body{margin:0;padding:0}
  *{box-sizing:border-box}
  .card{width:${W}px;height:${H}px;position:relative;overflow:hidden;
    background:linear-gradient(160deg,#7A67FF 0%,#6B59EB 46%,#5B4BD6 100%);
    font-family:"Segoe UI","Helvetica Neue",Arial,sans-serif}
  .orb{position:absolute;border-radius:50%;background:#fff;opacity:.06}
  .orb1{width:520px;height:520px;right:-190px;top:-210px}
  .orb2{width:360px;height:360px;left:-160px;bottom:-120px;opacity:.05}
  .copy{position:absolute;left:72px;right:72px;top:${card ? 1180 : 104}px;text-align:center}
  h1{margin:0;color:#fff;font-size:${card ? 84 : 62}px;line-height:1.08;font-weight:800;letter-spacing:-1.6px}
  p{margin:24px 0 0;color:#E4DEFF;font-size:${card ? 38 : 30}px;line-height:1.35}
  .mark{position:absolute;left:50%;transform:translateX(-50%);top:620px;
    width:300px;height:300px;border-radius:50%;background:rgba(255,255,255,.17);
    display:grid;place-items:center}
  .mark img{width:200px;height:200px;display:block}
  /* Dark rounded rect the video sits inside — the bezel is the few px of it
     that show around the overlaid frame. */
  .phone{position:absolute;left:${PHONE_X}px;top:${PHONE_Y}px;
    width:${SCREEN_W + BEZEL * 2}px;height:${SCREEN_H + BEZEL * 2}px;
    background:#14111c;border-radius:${BEZEL * 3}px;
    box-shadow:0 30px 70px rgba(26,16,74,.45)}
</style></head>
<body><div class="card">
  <div class="orb orb1"></div><div class="orb orb2"></div>
  ${mark}${phone}
  <div class="copy"><h1>${headline}</h1><p>${support}</p></div>
</div></body></html>`;
}

rmSync(WORK, { recursive: true, force: true });
mkdirSync(WORK, { recursive: true });
// The mark the intro/outro use is the app's own asset, not a redrawn one.
execFileSync('cp', [resolve(ROOT, 'graphics/src/white_head.png'), resolve(WORK, 'head.png')]);

const segments = [];
console.log('Rendering backgrounds and segments\n');

for (const s of SCENES) {
  const bg = resolve(WORK, `${s.id}.png`);
  const html = resolve(WORK, `${s.id}.html`);
  writeFileSync(html, cardHtml(s));
  execFileSync(CHROME, [
    '--headless', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
    `--window-size=${W},${H}`,
    `--screenshot=${bg.replace(/\//g, '\\')}`,
    `file:///${html.replace(/\\/g, '/')}`,
  ], { stdio: 'pipe' });

  const seg = resolve(WORK, `${s.id}.mp4`);
  if (s.card) {
    execFileSync(FFMPEG, [
      '-y', '-loop', '1', '-i', bg, '-t', String(s.dur),
      '-r', '30', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', seg,
    ], { stdio: 'pipe' });
  } else {
    const clip = resolve(RAW, s.src);
    if (!existsSync(clip)) throw new Error(`missing ${s.src}`);
    // Seek with the trim FILTER, not -ss on the input. screenrecord writes
    // very few keyframes, so input seeking lands on the nearest one and can
    // yield a single frame — which is exactly what it did before this change.
    // trim decodes from the start and is frame-accurate.
    execFileSync(FFMPEG, [
      '-y',
      '-loop', '1', '-i', bg,
      '-i', clip,
      '-filter_complex',
      // fps=30 FIRST. Android screenrecord is variable-rate: it emits a frame
      // only when the screen changes, so a clip that waits on a network call
      // can average 8fps with long gaps. trim on that timeline returns almost
      // nothing. Normalising to constant 30fps makes the seconds real again.
      `[1:v]fps=30,trim=start=${s.start}:duration=${s.dur},setpts=PTS-STARTPTS,` +
      `crop=${SRC_W}:${CROP_H}:0:${CROP_TOP},scale=${SCREEN_W}:${SCREEN_H}[v];` +
      `[0:v][v]overlay=${SCREEN_X}:${SCREEN_Y}:shortest=1[o]`,
      '-map', '[o]', '-t', String(s.dur),
      '-r', '30', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', seg,
    ], { stdio: 'pipe' });
  }
  segments.push(seg);
  console.log(`  ✅ ${s.id.padEnd(10)} ${s.dur}s`);
}

const list = resolve(WORK, 'concat.txt');
writeFileSync(list, segments.map((p) => `file '${p.replace(/\\/g, '/')}'`).join('\n'));
const final = resolve(OUT, 'speak-frankly-promo.mp4');
execFileSync(FFMPEG, [
  '-y', '-f', 'concat', '-safe', '0', '-i', list,
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-movflags', '+faststart', final,
], { stdio: 'pipe' });

const total = SCENES.reduce((a, s) => a + s.dur, 0);
const kb = readFileSync(final).length / 1024;
console.log(`\n🎬 video/speak-frankly-promo.mp4  ${W}x${H}  ${total.toFixed(1)}s  ${(kb / 1024).toFixed(1)} MB`);
