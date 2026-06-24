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

## Screenshot copy reference (matches screenshots-v3.html)

| # | Eyebrow                        | Headline              | Sub                                          |
|---|--------------------------------|-----------------------|----------------------------------------------|
| 1 | Step 1 - Split the song        | One song. Four stems. | Vocals, melody, drums, and bass appear in separate lanes you can play right away. |
| 2 | Step 2 - Import from Files     | Bring in any track from Files. | MP3, WAV, AIFF, or M4A. Pick a song and drop it straight into Stemacle. |
| 3 | Step 3 - Real spectrogram      | See the actual spectrogram. | Each stem gets its own time view, cursor, and seek lane. |
| 4 | Step 4 - Practice the part you need | Loop it. Solo it. | Mute the rest and build the mix you want to study. |

---

## Export guide

Screenshots are designed at 428×926 CSS pixels (1× logical).
To produce 1284×2778 PNG files (accepted iPhone 6.5" size):

**Option A — Self-contained exporter**
```bash
npm run appstore:export-iphone
```

**Option B — Chrome DevTools**
1. Open screenshots-v3.html in Chrome
2. DevTools → More tools → Sensors → Device pixel ratio: 3
3. Set viewport to 428×926
4. Screenshot each .shot div individually

**Option C — puppeteer script**
```js
const puppeteer = require('puppeteer');
const browser = await puppeteer.launch({ defaultViewport: { width: 428, height: 926, deviceScaleFactor: 3 } });
const page = await browser.newPage();
await page.goto('http://localhost:7892/appstore-screenshots/screenshots-v3.html');
for (let i = 1; i <= 4; i++) {
  const shot = await page.$(`#s${i}`);
  await shot.screenshot({ path: `shot-${i}.png` });
}
await browser.close();
```
