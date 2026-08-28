# Promo video

`speak-frankly-promo.mp4` — 1080x1920 (9:16), 43.6s, voice + music.

Built entirely from real `adb screenrecord` captures in `raw/`, composed into
the same device frame the screenshots use, so the listing reads as one piece.

## Building

```
node scripts/build-video.mjs        # silent cut + video/scenes.json
python scripts/build_promo_audio.py # voiceover, music, mix
```

The first pass writes `speak-frankly-promo-silent.mp4` and a scene map. The
second reads that map so every line lands on the scene it belongs to, then
muxes — the video stream is copied, never re-encoded.

## Sound

Voice is neural Indian-English TTS (`en-IN-NeerjaNeural`) — the accent the
primary market actually hears in Indian advertising, and the same voice used by
the ad creatives in `marketing/google-ads`, so the listing and the ads sound
like one product.

The music bed is **synthesised from a chord progression in code**
(`marketing/google-ads/build_music.py`), not downloaded. A bed lifted from a
free-music site is only as safe as its licence, and a bad one means a copyright
claim on the YouTube upload. Nothing here needs clearing.

A sidechain compressor ducks the bed while the voice speaks and lets it back up
in the gaps. One line per scene; the rest of each scene stays quiet, which is
how a real ad mix breathes.

## Play only takes a YouTube URL

There is no file upload for the promo video. Put this on YouTube (public or
unlisted, **ads turned off**, not age-restricted), then paste the watch URL into
the Play Console listing.

## A real bug this recording exposed

The first take of the chat scene caught the app showing its own timeout message
— "Hmm, I didn't catch that. Could you say it again?" — instead of a reply. That
was not a fluke worth editing around:

- `/health` reported the AI call had **succeeded** on the server
  (`calls: 1, ok: 1, failed: 0`).
- Warming the backend by hand measured a **21.4 second** cold start on the first
  request, then 0.25s once awake.
- The app gives up at **30 seconds** (`_timeout` in `api_service.dart`).

So on Render's free tier, a real learner opening the app after the backend has
slept can send their first message, wait, and be told the tutor did not catch it
— while the server answers fine a moment later. `ApiService.warmup()` fires on
launch and helps, but not if the learner starts talking quickly.

The scene here was re-recorded against a warm backend. The underlying timeout is
still worth fixing.

## Editing the cut

`SCENES` in `scripts/build-video.mjs` holds the order, the trim window into each
raw clip (`start`, `dur`), the on-screen caption and the spoken line. Change it
there and rerun both steps.

Two things about Android `screenrecord` that cost real time here:

- It records **variable frame rate** — a frame only when the screen changes. The
  chat clip, which waits ten seconds on a network call, averages 8fps with long
  gaps. Trimming on that timeline returned a single frame. Every clip is
  normalised to 30fps before trimming.
- Its **MP4 duration header lies**, so `-ss` input seeking lands on whatever
  sparse keyframe it can find. The build seeks with the `trim` filter instead.
