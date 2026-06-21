# Stemacle — App Store Connect Copy

## App Name
Stemacle

## Subtitle (30 chars max — current: 28)
Stem Splitter, Loop & Solo

## Promotional Text (170 chars max — can be updated anytime; current: 148)
Split any track into drums, bass, vocals, and melody, on your device. No uploads, no account. Loop any stem, solo any stem. $2.99, once.

## Description (4000 chars max)

Drop any audio file. Stemacle splits it into four stems, on your device.

Drums. Bass. Vocals. Melody.

No uploads. No server. No account. Your music stays yours.

---

FOUR STEMS FROM ANY TRACK

Stemacle uses a local ML model to separate any audio file you give it: MP3, WAV, AIFF, M4A. The four stems appear in seconds and are immediately playable, mutable, and loopable. The model runs entirely on-device. Your audio never leaves your phone.

PLAY THE WAY YOU WANT

Each stem has its own volume, mute, solo, and loop controls. Loop any stem at 1/4, 1/2, 1, or 2 measure lengths, independently. Link all four stems with a single All row to lock them in step. Swap between Mix mode (looped stems play against the full track) and Solo mode (the looped stem cues through headphones without changing your mute state).

SEE THE MUSIC

A full-width spectrogram for each stem shows you what you are hearing. Tap anywhere on a stem to seek within the visible window. The display follows active loops automatically, expanding to show the earliest looped stem and current transport position.

YOUR LOCAL LIBRARY

Add tracks from Files and keep a local history of the songs you have already split. Your library lives on your device. No sign-in, no sync, no subscription required.

WHAT STEMACLE DOES NOT DO

It does not stream. It does not suggest. It does not connect to any service. It does not share your data. After the first model download it runs fully offline. It is a tool, not a platform.

---

One-time purchase. No in-app purchases. No subscription.

## Keywords (100 chars max — current: 98)
stem splitter,vocal remover,demucs,music remix,karaoke,isolate vocals,drum track,bass isolate,loop

## Price
$2.99 (Tier 3)

## Support URL
https://stemacle.com/support

## Privacy Policy URL
https://stemacle.com/privacy

## What's New (first submission — leave blank or use below)
First release. Drop any track and Stemacle splits it into drums, bass, vocals, and melody, right on your device.

---

## Screenshot copy reference (matches screenshots.html)

| # | Eyebrow                        | Headline              | Sub                                          |
|---|--------------------------------|-----------------------|----------------------------------------------|
| 1 | Stemacle · Stem Splitter       | Drop any track.       | It splits into four stems on your device.    |
| 2 | On-device ML · No cloud        | Four stems, instantly.| Separated locally. Never uploaded.           |
| 3 | Any format · MP3, WAV, AIFF, M4A | Drop it. Watch it split. | (none — headline carries)               |
| 4 | Loop · Solo · Mute             | Every stem, your call.| Loop one. Solo another. Build your own mix.  |
| 5 | Local-first · Private by default | No uploads. No account. Yours. | $2.99, once. No subscription.  |

---

## Export guide

Screenshots are designed at 430×932 CSS pixels (1× logical).
To produce 1290×2796 PNG files (required for iPhone 6.7"):

**Option A — Chrome DevTools**
1. Open screenshots.html in Chrome
2. DevTools → More tools → Sensors → Device pixel ratio: 3
3. Set viewport to 430×932
4. Screenshot each .shot div individually

**Option B — puppeteer script**
```js
const puppeteer = require('puppeteer');
const browser = await puppeteer.launch({ defaultViewport: { width: 430, height: 932, deviceScaleFactor: 3 } });
const page = await browser.newPage();
await page.goto('http://localhost:7892/appstore-screenshots/screenshots.html');
for (let i = 1; i <= 5; i++) {
  const shot = await page.$(`#s${i}`);
  await shot.screenshot({ path: `shot-${i}.png` });
}
await browser.close();
```

**Option B, run from project root:**
```bash
cd /Users/eric/GitHub/stem-player
npx puppeteer@latest node appstore-screenshots/export.js
```
