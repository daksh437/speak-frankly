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

## KNOWN FLAW — re-record before publishing

The chat scene shows a failed exchange above the good one:

> Hmm, I didn't catch that. Could you say it again?

That is the app's own client-side timeout message. It appeared because the
Render free-tier backend was cold and took longer than the app's 30-second HTTP
timeout to answer. The retry immediately below it worked and produced the
correction the scene is about — but a promo video should not show the app
failing.

To fix: force-stop the app (chat history is not persisted, so it reopens clean),
open Job Interview against a WARM backend, type a sentence containing an error,
and record about 20 seconds from the moment you send. Save over
`raw/c2-chat.mp4` and rerun both build steps.

That timeout deserves attention on its own: a real user opening the app after
the backend has slept hits exactly the same failure on their first message.

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
