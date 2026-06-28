# Stemacle Native Apps Wishlist

Starting fresh with the web app as the gold master (`stemacle.com/app`), this defines the vision for desktop and iOS native surfaces when rebuilt.

## Why People Will Pay

**Desktop** ($4.99/month or $39.99/year) justifies itself through:
- Batch splitting: split 100 songs while you sleep
- Stems to DAW: drag stems directly into Logic, Ableton, or Reaper
- Advanced exports: MIDI note detection, acapella isolation, instrumental stems
- Unlimited stem history: keep 100+ projects organized and researchable
- Premium models: access experimental or high-quality separators beyond base
- Background processing: queue jobs, work in other apps, get notified when done
- Local library indexing: automatically organize music folders on disk
- Audio analysis: BPM detection, key detection, spectral analysis dashboard
- Recording studio: mic + instrument input, record jams over separated stems
- Preferences sync: backup projects and settings

**iOS** ($2.99 upfront, then optional $1.99/month for premium) drives value through:
- Instant splitting on-the-go: download a song, split it in 30 seconds
- Creator mode: record vocal over instrumental, export stems for collaboration
- Offline-first: no internet required after app download
- Unlimited splitting: pay once, split as many songs as you want
- Share stems: send isolated vocals/instrumental to bandmates via AirDrop/email
- Spotify/Apple Music bridge: find songs, download preview, split, remix
- Voice memo remixing: record voice memo, get instant beats behind it
- Stem remix playground: layer stems differently, save variations
- Project cloud backup: (future) sync projects across devices
- Premium: exclusive DSP models, advanced effects, stem effects chains

**Engagement Drivers:**
- 🎵 Spotify/Apple Music integration (search → preview → download → split workflow)
- 🎤 Recording mode: mic input, split in real-time, layer with stems
- 🎚️ Stem remix playground: drag stems, adjust pitch/time, save as new audio
- 📁 Local library: watch a folder, auto-split new songs added
- 🔄 Share stems: collaborative music editing (send vocals to producer, get back mix)
- 📊 Creator analytics: see what stems are most used, A/B test remixes
- 🎯 Sample store: premium stems packs, loops, one-shots (future revenue)

## Core Product DNA (Both Platforms)

Non-negotiable from the web app:
- [ ] Warm matte circle as primary visual signal
- [ ] Four-stem model: drums, bass, vocals, melody
- [ ] Transport controls: play, pause, stop, restart, seek
- [ ] Per-stem mute, headphones isolation, volume
- [ ] Spectrogram lanes with visible-window scrubbing
- [ ] Per-stem play cursors
- [ ] Loop buttons: per-stem 1/4, 1/2, 1, 2 measure loops
- [ ] All-stem linked loops with per-stem independence
- [ ] Tempo detection and loop snapping to grid
- [ ] Mix/Solo loop monitoring
- [ ] Loop rejection (won't run past track end)
- [ ] Persistent global mute without resetting per-stem volumes
- [ ] File load resets loops
- [ ] Sample tracks for testing
- [ ] Restrained visual chrome—no dashboard competing with the instrument

## Desktop (macOS + SwiftUI)

### Goalpost 1: Parity Release (MVP)
**Goal:** Free or $4.99 one-time. Make people realize native is worth installing.

- [ ] SwiftUI app shell in `native/macos`
- [ ] Load prepared local `/app/` bundle via WKWebView
- [ ] Warm matte circle, four-stem controls, loop contract match web exactly
- [ ] Play/pause/seek/tempo/loop behavior identical to web
- [ ] Native file dialogs (NSOpenPanel for one-off splits)
- [ ] Project history—save and recall loop ideas
- [ ] Basic export: WAV stems to disk
- [ ] Keyboard shortcuts and native menu bar
- [ ] App Store packaging ready

**Why it matters:** People see this and think, "Oh, native splitting is actually cool."

---

### Goalpost 2: Creator Studio ($4.99/month or $39.99/year)
**Goal:** Professional creators (producers, DJs, remix artists) pay monthly.

**Core Additions:**
- [ ] **Recording studio**: Mic + line input, record jams with stems playing underneath
  - [ ] Real-time stem playback during recording
  - [ ] Level meters and gain staging
  - [ ] Overdub mode (layer recordings)
  - [ ] Save stems + recording as separate tracks
  - [ ] Export as multitrack project file (MIDI + stems)
- [ ] **DAW bridge**: Drag stems directly to Logic, Ableton, Reaper (native file handlers)
  - [ ] Inter-app audio (IAA) on macOS
  - [ ] Create Finder quick actions: "Open in Ableton" workflow
  - [ ] Smart export: stems + BPM/key metadata
- [ ] **Advanced exports**:
  - [ ] MIDI note detection from vocals (convert melody to MIDI)
  - [ ] Acapella isolation (clean vocal-only export)
  - [ ] Instrumental stem mixing
  - [ ] Stems with fade/crossfade for mashups
  - [ ] Stems with time-align correction
- [ ] **Unlimited project history**: Keep 100+ splits organized
  - [ ] Star favorite projects
  - [ ] Auto-tag by artist/genre
  - [ ] Full-text search
  - [ ] Drag to compare (A/B visualizer)
- [ ] **Batch processing**: 
  - [ ] Queue 100 files, walk away, come back to organized stems
  - [ ] Recursive folder processing
  - [ ] Custom naming templates
  - [ ] Auto-organization: `[Artist] - [Song]/[Stem]`
- [ ] **Stem remix playground**:
  - [ ] Adjust stem pitch independently
  - [ ] Time-stretch stems without pitch shift
  - [ ] Layer multiple stems, save as new audio
  - [ ] A/B compare original vs remix
- [ ] **Audio analysis dashboard**:
  - [ ] BPM detection (display detected tempo)
  - [ ] Key detection
  - [ ] Loudness analysis (LUFS)
  - [ ] Frequency spectrum per stem
  - [ ] Loudness matching (normalize stems)
- [ ] **Settings**: Model selection, export location, temp cache management
- [ ] **Preferences sync** (future): iCloud backup of projects and settings

**Why it matters:** Producers realize they can remix, record, and export to DAW without hunting for tools. One app for stem splitting + creation.

---

### Goalpost 3: Content Creator Workflow (Premium $8.99/month)
**Goal:** Podcasters, DJs, TikTok creators want to remix songs at scale.

- [ ] **Song library auto-watch**: Point at a folder, auto-split new downloads
- [ ] **Local library indexing**: 
  - [ ] Search by artist, BPM, key
  - [ ] Smart playlists ("all 120 BPM uplifting songs")
  - [ ] Recently added, most-used stems
- [ ] **Spotify/Apple Music bridge** (future web server consideration):
  - [ ] Search Spotify, preview 30-second clip
  - [ ] Add to "split queue" and auto-download + split
  - [ ] Stem covers: see remixes other creators made of same song
- [ ] **Stems to cloud** (future):
  - [ ] Upload stems to project folder for bandmate download
  - [ ] Version control: keep stems from different split attempts
- [ ] **Creator analytics** (local only, for now):
  - [ ] Most-used stems
  - [ ] Stems you've exported (track what you actually use)
  - [ ] Time-to-split metrics (which songs take longest)
  - [ ] Model performance (which models you prefer)
- [ ] **Stem effects chains** (advanced remix):
  - [ ] Reverb, delay, distortion per stem
  - [ ] EQ and dynamics
  - [ ] Stem ducking (auto-lower bass when vocals play)
  - [ ] Save effect chains as templates
- [ ] **Export bundles**:
  - [ ] Stems + original + remix as a pack
  - [ ] Stems with metadata (BPM, key, duration)
  - [ ] Stems in multiple formats (WAV, MP3, M4A)

**Why it matters:** People go from "splitting songs is cool" to "I'm building a remix catalog professionally."

## iOS (SwiftUI + Native Audio)

### Goalpost 1: Parity Release (Free)
**Goal:** Anyone on iOS can split songs like the web app. No barriers.

- [ ] SwiftUI app shell from `AppDelegate`
- [ ] Load prepared local `/app/` bundle
- [ ] Stemacle circle, four-stem controls, loop contract match web exactly
- [ ] Play/pause/seek/tempo/loop behavior identical to web
- [ ] Compact, thumb-reachable controls
- [ ] Document picker (open songs from Files, iCloud, Music app)
- [ ] Recent projects list
- [ ] Export stems via share sheet
- [ ] Haptics on transport and mute
- [ ] iPad responsive layout
- [ ] App Store ready

**Why it matters:** People have Spotify, download songs, instantly split them on phone. No computer needed.

---

### Goalpost 2: Creator Mode ($2.99 upfront)
**Goal:** Singers, rappers, producers use iOS as a creative tool, not just a player.

- [ ] **Voice recording mode**:
  - [ ] Mic input while stems play
  - [ ] Record vocal over any song's instrumental
  - [ ] Multitrack: record drum loop, then add vocal, then guitar
  - [ ] Record voice memos and auto-split them
  - [ ] Level metering and gain control
  - [ ] Undo/redo for recordings
- [ ] **Instant stem export**:
  - [ ] Share stems via AirDrop to Mac/PC
  - [ ] Email stems to producer/bandmate
  - [ ] iCloud Files export (accessible from any device)
  - [ ] Save to Photo Library as audio
- [ ] **Collaborative remixing**:
  - [ ] Receive stems from collaborator, add your vocal
  - [ ] Send back isolated vocal for producer to mix
  - [ ] Project file format: includes all stems + metadata
- [ ] **Stem remix playground**:
  - [ ] Adjust stem volume balance
  - [ ] Pitch shift individual stems
  - [ ] Layer stems differently, save remix as audio
  - [ ] A/B compare original vs your remix
- [ ] **Unlimited splitting**: No limits on songs you split
- [ ] **Search + quick split workflow**:
  - [ ] Search your music library by artist
  - [ ] One tap: download song preview → split → play
  - [ ] See frequently split songs (artists you love)
- [ ] **Local project organization**:
  - [ ] Star favorite splits
  - [ ] Auto-organize by artist/genre
  - [ ] Quick access to "my recordings"

**Why it matters:** Singer wants to send vocal recordings to producer. One app handles recording, splitting, mixing preview, and sharing.

---

### Goalpost 3: Spotify/Apple Music Bridge ($1.99/month, Premium tier)
**Goal:** Streamlined song → split → remix workflow. Download → split in 30 seconds.

- [ ] **Music service integration** (future web server can power this):
  - [ ] Search Spotify, Apple Music, YouTube Music
  - [ ] Preview 30-second clip in-app
  - [ ] Download preview, auto-split
  - [ ] See stems other creators made of same song
  - [ ] Follow creators (future: social feed)
- [ ] **Smart download queue**:
  - [ ] Add songs to "split later" queue
  - [ ] Batch download + split over WiFi
  - [ ] Auto-organize downloaded stems by artist
- [ ] **Stem covers community** (future):
  - [ ] See popular remixes of any song
  - [ ] Listen to how others split the same track
  - [ ] One-tap: download their stems, layer with yours
- [ ] **Creator profile** (future):
  - [ ] Share your best remixes
  - [ ] Followers can use your stem versions
  - [ ] See your remix stats
- [ ] **Offline-first architecture**:
  - [ ] Download songs, stems stay on device
  - [ ] No internet needed to remix
  - [ ] Auto-sync when WiFi available

**Why it matters:** Casual music fan becomes creator. Search Spotify, find song, split, record vocal, share with friends in under 2 minutes.

---

### Goalpost 4: Advanced Audio (Premium $4.99/month)
**Goal:** Serious producers get pro-level splitting and effects on mobile.

- [ ] **Native audio separation** (`NativeStemSplitter`):
  - [ ] Short clips: spectral DSP (STFT, masking, ISTFT)
  - [ ] Long tracks: IIR preview (fast, real-time)
  - [ ] Smart switching: detect length, choose fastest path
  - [ ] High-quality models: experimental separators beyond base
- [ ] **Stem effects**:
  - [ ] Per-stem EQ (3-band)
  - [ ] Per-stem reverb and delay
  - [ ] Stem ducking (vocals lower bass automatically)
  - [ ] Saturation, compression per stem
  - [ ] Save effect chains as presets
- [ ] **Audio analysis**:
  - [ ] BPM detection
  - [ ] Key detection
  - [ ] Loudness matching (normalize stems)
  - [ ] Frequency spectrum per stem
- [ ] **Advanced exports**:
  - [ ] Multitrack AAC (if iOS supports)
  - [ ] Stems in multiple formats
  - [ ] Stems + BPM/key metadata
  - [ ] Loop regions (export only chorus)
- [ ] **Background splitting** (iOS 13+):
  - [ ] Queue songs, app splits in background
  - [ ] Get notification when done
  - [ ] Don't lock phone during splitting
- [ ] **iCloud sync** (future):
  - [ ] Projects sync across iPhone/iPad/Mac
  - [ ] Stems accessible from desktop
  - [ ] Collaborate in iCloud Shared Folder

**Why it matters:** Producer doesn't need computer. Full creative suite in pocket. Record, split, remix, export, share—all on phone.

## Architecture Decisions

### What NOT to do
- ❌ No Electron wrapper for desktop
- ❌ No Cordova/Capacitor for iOS (native Swift compiles Stemacle)
- ❌ No desktop Demucs worker pipeline
- ❌ No OS folder recursion on iOS
- ❌ No Finder integration on iOS (sandboxing)

### What to do
- ✅ SwiftUI for both macOS and iOS
- ✅ WKWebView for web bundle on desktop (at first)
- ✅ Native Swift separation code for iOS audio (`NativeStemSplitter`)
- ✅ App sandbox entitlements from day one
- ✅ App Store distribution path built in
- ✅ Local-first storage, durable cache paths
- ✅ Zero network requirement (offline-first)

## Release Goalposts Roadmap

**Q1 2026: Goalpost 1 (Free/MVP)**
- [ ] Desktop: File splitting + parity with web
- [ ] iOS: Free splitting + voice recording
- [ ] Goal: 10k installs, proof of concept

**Q2 2026: Goalpost 2 (Creator Studio)**
- [ ] Desktop: DAW bridge, recording, batch processing
- [ ] iOS: Instant stem export, multitrack recording
- [ ] Goal: 1st paid tier launch, recurring revenue starts

**Q3 2026: Goalpost 3 (Scale)**
- [ ] Desktop: Unlimited project history, advanced exports
- [ ] iOS: Spotify/Apple Music bridge (with future web server)
- [ ] Goal: Creator community, social sharing

**Q4 2026: Goalpost 4 (Pro)**
- [ ] Desktop: Stem effects, analytics, preferences sync
- [ ] iOS: Background splitting, iCloud sync, advanced audio
- [ ] Goal: Professional users, word-of-mouth growth

---

## Release Checklist (When Rebuilt)

**Goalpost 1 Checklist:**
- [ ] Web bundle: `npm run site:prepare` (unchanged)
- [ ] Web app at `stemacle.com/app` stays perfect
- [ ] Desktop: SwiftUI file splitter MVP
- [ ] iOS: Free splitter + document picker
- [ ] Regression suite: `npm test` (web parity tests)
- [ ] All surfaces verify: same four-stem behavior, loop contract, visual identity

**Goalpost 2+ Additions:**
- [ ] Desktop: IAA/file handlers for DAW integration
- [ ] iOS: AVFoundation recording, multitrack support
- [ ] Payment integration (Stripe, App Store IAP)
- [ ] Analytics (Posthog or similar): track feature usage, revenue
- [ ] Release notes per goalpost highlight value-add

## Navigation Flow (When Ready)

### Desktop Tabs
1. Stem Splitter (primary)
2. Library (local projects)
3. Stem Shuffle
4. Settings

### iOS Tabs
1. Splitter (primary)
2. Shuffle
3. Projects (history)
4. Library
5. Settings

---

## Future: Web Server (Keep in Back of Mind)

The native apps start **offline-first and local-only**. No server required. But once we have enough creators, a web server unlocks:

### Discovery & Community (Backend service, future consideration)
- **Stem covers**: Users upload splits of popular songs → others find and remix them
  - Spotify/Apple Music integration: link songs to splits
  - Creator profiles: showcase your best stem versions
  - Feed: discover trending remixes
- **Song database**: Catalog songs, splits, BPM/key metadata
  - Creator can search: "Who else split this song? How did they approach it?"
  - Statistics: How many splits does each song have? Most remixed songs?
- **Collaboration**: Share projects with others
  - Send stems to producer, get back mix
  - Work on remix with bandmate in real-time (future)
  - Version history: keep splits from different DSP models

### Creator Economics (Backend service, future consideration)
- **Splits marketplace**: Creators sell premium stem packs
  - "This DJ split 100 Afrobeats tracks"
  - Buyers pay $5 for the collection
  - Creator gets 70% cut (like App Store)
- **Creator analytics**: Cross-device insights
  - What stems are most popular?
  - Which songs should you remix next?
  - Revenue from splits sold
- **AI recommendations**: Suggest songs to split based on your taste
  - "5 new 120 BPM Techno songs dropped, want to split them?"

### Deployment
- **Mobile-first**: Build native apps first (offline works)
- **Server second**: Add optional backend once creators need discovery/sharing
- **No lock-in**: Users can always export stems to files and work offline
- **Privacy-first**: Server is optional. Don't require account creation.

**Principle**: Apps are compelling enough to sell on their own. Server is a future growth layer, not a requirement.

---

## Pricing Strategy (Phased)

### Desktop
- **Goalpost 1**: Free (Freemium trial)
- **Goalpost 2**: $4.99/month or $39.99/year (Creator Studio)
- **Goalpost 3**: Add $8.99/month tier (Content Creator with analytics)
- **Future**: Premium models, sample packs ($1.99 each)

### iOS
- **Goalpost 1**: Free
- **Goalpost 2**: $2.99 upfront (Creator Mode)
- **Goalpost 3**: Optional $1.99/month (Spotify bridge + features)
- **Goalpost 4**: Optional $4.99/month (Pro audio + background splitting)
- **Future**: Premium models, sample packs ($0.99 each)

### Revenue Model Rationale
- **Desktop**: Monthly subscription (creators live on computer, will pay recurring)
- **iOS**: One-time purchase + optional subscriptions (mobile users expect low friction)
- **Freemium layer**: Free splitting hooks people, paid tiers unlock creator workflows
- **Server features** (future): Splits marketplace, premium models, analytics subscriptions

---

**Goal**: One Stemacle identity across web, desktop, and iOS. The web app is perfect and canonical. Desktop and iOS are separate native surfaces that respect the same product DNA while adding platform-native power.

**The ask**: Make it so compelling that:
1. Casual user thinks, "This app is magic, I'll pay $2.99"
2. Creator thinks, "This is my remix studio, worth $5/month"
3. DJ/producer thinks, "I can't work without this"
4. Future: Creator ecosystem (stems marketplace, collaborations, profiles) makes server viable
