# Promo video

`speak-frankly-promo.mp4` — 1080x1920 (9:16), 45s, no audio.

Built from real `adb screenrecord` captures in `raw/`, composed into the same
device frame the screenshots use, so the listing reads as one piece. Rebuild
with:

```
node scripts/build-video.mjs
```

## Play only takes a YouTube URL

There is no file upload for the promo video. Upload this to YouTube (public or
unlisted, **ads turned off**, not age-restricted), then paste the watch URL into
the Play Console listing.

## KNOWN FLAW — re-record before publishing

The chat scene (8.5s–21.5s) shows a failed exchange above the good one:

> Hmm, I didn't catch that. Could you say it again?

That is the app's client-side timeout message. It appeared because the Render
free-tier backend was cold and took longer than the app's 30-second HTTP
timeout to answer. The retry directly below it worked and produced the
correction the scene is about — but a promo video should not show the app
failing.

To fix: force-stop the app (chat history is not persisted, so it reopens
clean), open Job Interview with a WARM backend, type a sentence containing an
error, and record about 20 seconds from the moment you send. Save over
`raw/c2-chat.mp4` and rerun the build script.

## No audio, on purpose

`screenrecord` captures none, and adding unlicensed music invites a copyright
claim on the YouTube upload. The captions carry the story, which is how store
videos are watched anyway.

## Scene timings

Edit the `SCENES` array in `scripts/build-video.mjs` to change the cut. `start`
and `dur` are seconds into the raw capture.

Note that Android screenrecord writes VARIABLE frame rate — it only emits a
frame when the screen changes, so a clip that waits on a network call can
average 8fps. The build script normalises each clip to 30fps before trimming;
without that, `trim` on those timestamps returns almost nothing.
