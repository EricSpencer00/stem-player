# Stemacle Native Product Design

## Goal

Turn the desktop and iOS apps into native parity-plus versions of the perfect Stemacle web app.

The web app at `https://stemacle.com/app/` is already perfect. `https://ericspencer.us/stem-player` points to that same canonical app. Native work must not reinterpret the core product. Desktop and iOS must first match the web app's splitter experience, then go above and beyond with native organization, storage, import, project, export, and platform polish.

## Product Position

Stemacle should feel like:

- a quiet indie music app
- a local-first creative tool
- a small but considered product with strong taste

Stemacle should not feel like:

- a responsive website in a desktop frame
- a SaaS dashboard with music features
- a DAW clone
- a generic AI tool with trendy gradients and glass panels

## Chosen Direction

Adopt a **web-parity-first native shell** for both desktop and iOS, then layer a project-centric native product around it.

This means:

- the perfect web app is the gold master for splitter behavior and feel
- the native Stem Splitter must preserve the same controls, timing contract, visual hierarchy, and tactile restraint before adding anything else
- `Project` is the primary object in the app
- `Home` and `Projects` are first-class destinations
- `Stem Splitter` and `Stem Shuffle` are project tools, not isolated routes
- `Library`, `Queue`, `Exports`, and `Settings` support project work rather than competing with it

This is the right middle ground between a launcher shell and a full DAW:

- more native and coherent than a route launcher
- much lighter and more legible than a timeline-heavy workstation
- faithful to the perfect browser instrument before adding native power

## Core Product Objects

### Project

A project is the main unit of work. It represents one creative thread around a source track or saved pairing idea.

Each project holds:

- project id
- project name
- cover artwork or waveform thumbnail
- source track reference
- created and last-opened timestamps
- current stem analysis status
- saved loop ideas
- saved shuffle pair ideas
- export history
- lightweight notes

### Library Track

A library track is a reusable source asset that can be used in one or many projects.

Each library track persists:

- track id
- file name
- source path or iOS-local storage reference
- duration and format metadata
- waveform thumbnail
- analysis availability
- project usage count

### Queue Job

A queue job is background work owned by the native shell.

Kinds:

- import
- analysis
- download desktop only
- export

### Export Record

An export record represents a finished or pending user-facing output.

Each export record tracks:

- export id
- project id
- output kind
- output format
- destination
- created timestamp
- completion status

## Platform Roles

## Desktop

Desktop is the full SwiftUI local workbench. It must match the web app first, then use native desktop capabilities to exceed what the browser can responsibly own.

Desktop owns:

- SwiftUI app structure and native desktop polish
- a splitter surface that matches the perfect web app's controls and loop behavior
- persistent library indexing
- folder roots
- background queue execution
- model and tool capability state
- high-quality analysis
- export directory ownership
- reveal-in-Finder actions
- URL-based download ingestion when desktop tools are available

## iOS

iOS is the focused SwiftUI mobile companion. It must match the web app first, then use mobile-native patterns to make Stemacle feel inevitable on touch devices.

iOS owns:

- a native splitter surface that matches the perfect web app's controls and loop behavior
- touch-first project access
- file import from Files and share sheet
- lightweight local library
- reopening recent projects
- mobile entry into Splitter and Shuffle
- mobile export and sharing flows

iOS explicitly does not own:

- unrestricted folder recursion
- Finder-style file reveal actions
- full desktop queue management
- desktop-grade model administration
- terminal-adjacent tool plumbing

## Shared Product Principles

### 1. Web parity comes first

`https://stemacle.com/app/` is the gold master. Desktop and iOS should not add project chrome, library state, settings, or new visual language at the expense of the working splitter. If a native decision conflicts with web parity, parity wins unless Eric explicitly changes the product direction.

### 2. Projects come after parity

The first question the app should answer is not “what tool do you want,” but “what are you working on.”

### 3. Splitter stays focused

The current Stem Splitter is a strong instrument. The native shell should frame it, not bury it in heavy chrome.

### 4. Shuffle is a sibling, not a separate universe

Stem Shuffle can have slightly newer energy, but it must still feel like Stemacle and live inside the same project model.

### 5. Native surfaces earn their weight

Every non-instrument screen must justify itself through organization, recall, or output management. No decorative admin screens.

### 6. Local-first is visible

Users should understand that their tracks, caches, and exports live on their device without reading a privacy essay.

## Information Architecture

## Desktop Navigation

Persistent sidebar destinations:

- `Home`
- `Projects`
- `Library`
- `Queue`
- `Exports`
- `Settings`

Top bar utilities:

- global search
- `New Project`
- quick import
- command palette
- compact status cluster for queue and storage state

Workspace destinations entered from content:

- `Stem Splitter`
- `Stem Shuffle`

## iOS Navigation

Primary tab or root-nav destinations:

- `Home`
- `Projects`
- `Library`
- `Settings`

Entered from project context:

- `Stem Splitter`
- `Stem Shuffle`

Presented as sheets or subordinate screens:

- export/share
- lightweight queue state
- rename/delete confirmations

## Screen Inventory

The screens below are required for v1 native polish. “Non-functional” here still means every visible button and state is specified, even where a backend behavior may still be staged.

## Shared Screens

### 1. First-Run Onboarding

Purpose:

- explain the product in one glance
- get the user to a useful first action fast

Layout:

- strong title
- short local-first explanation
- three primary entry actions

Buttons:

- `Import a Track`: opens file picker or Files on iOS
- `Try a Sample`: seeds the app with bundled content
- `Open Existing Library`: desktop opens the library surface directly
- `Skip for Now`: closes onboarding and lands on Home

States:

- first launch
- post-update “What’s New” variant when the app needs to call out a meaningful change

### 2. Home

Purpose:

- native app landing page
- immediate access to continue work

Required modules:

- recent projects strip
- primary creation area
- quick system status
- continue-where-you-left-off card when a recent project exists

Buttons:

- `New Project`
- `Import Track`
- `Resume Last Project`
- `Open Library`
- `Open Splitter`
- `Open Shuffle`

Rules:

- `Open Splitter` and `Open Shuffle` should open the active or most recent project when one exists
- when no project exists, those buttons should route through project creation instead of dropping the user into orphan tools

States:

- empty
- populated
- import in progress
- recent project unavailable

### 3. New Project Sheet

Purpose:

- create a clean project object before entering an instrument

Creation sources:

- local file
- library track
- bundled sample

Fields:

- project name defaulting to source track name

Buttons:

- `Cancel`
- `Create Project`
- `Create and Open Splitter`
- `Create and Open Shuffle`

Rules:

- source choice must be visually obvious
- only one primary action at a time should be emphasized

### 4. Project Detail

Purpose:

- the main hub for one project

Content:

- project title
- source track summary
- last-opened metadata
- stem analysis status
- saved loop ideas
- saved shuffle ideas
- export history
- notes

Buttons:

- `Open Splitter`
- `Open Shuffle`
- `Analyze HQ`
- `Export`
- `Rename`
- `Duplicate`
- `Archive`
- `Delete`
- `Reveal Source` desktop only
- `Share` iOS only

Rules:

- this page should make the project feel real even when no analysis has run yet
- the primary action changes based on state:
  - no analysis yet: `Open Splitter`
  - active loop work exists: `Resume Splitter`
  - saved shuffle idea exists: `Resume Shuffle`

### 5. Stem Splitter Workspace

Purpose:

- match the perfect web splitter first, then embed it as a project tool inside the native shell

Shell chrome:

- back to project
- project title
- save snapshot or save idea action
- open in shuffle
- export

Buttons outside the embedded instrument:

- `Back to Project`
- `Save Snapshot`
- `Open in Shuffle`
- `Analyze HQ`
- `Export`

Instrument behavior retained from web UI:

- load track
- play, pause, restart, stop
- seek
- mute and solo per stem
- stem volumes
- spectrogram lanes and play cursors
- linked and independent loop buttons
- mix and solo monitoring modes
- file-load loop resets
- loop rejection at the end of a track

Rules:

- once inside the splitter, shell chrome should recede
- the app should not feel like a browser with a sidebar still shouting for attention
- every native control added around the splitter must preserve the web app's timing and loop contract

### 6. Stem Shuffle Workspace

Purpose:

- embed the current shuffle surface as the second project tool

Shell chrome:

- back to project
- save transition idea
- return to splitter
- export current concept

Buttons outside the embedded instrument:

- `Back to Project`
- `Save Transition Idea`
- `Return to Splitter`
- `Export`

Instrument behavior retained from shuffle UI:

- load or choose compatible sources
- shuffle a pair
- play pair
- stop
- flip
- lead A
- blend
- lead B
- crossfader
- per-deck stem control

Rules:

- saved pair ideas belong to the project
- shuffle must not feel like a disconnected second app

## Desktop-Only Screens

### 7. Projects Index

Purpose:

- the main overview of all projects

Views:

- grid
- compact list

Filters:

- `Recent`
- `Needs Analysis`
- `Ready`
- `Exported`
- `Archived`

Buttons per row or card:

- `Open`
- `Rename`
- `Duplicate`
- `Archive`
- `Delete`

Global buttons:

- `New Project`
- `Import Track`
- `Sort`
- `Search`

### 8. Library

Purpose:

- own imported source media and folder-backed content

Content:

- track rows
- library roots
- metadata
- project usage
- import status

Buttons:

- `Add Music`
- `Add Folder`
- `Create Project`
- `Open Source`
- `Reveal in Finder`
- `Rescan`
- `Remove from Library`

Rules:

- library is about reusable sources, not in-progress creative state
- one track may spawn many projects

### 9. Queue

Purpose:

- show meaningful background work without becoming a noisy operations panel

Sections:

- `Imports`
- `Analysis`
- `Downloads`
- `Exports`

Buttons:

- `Pause All`
- `Resume All`
- `Retry`
- `Cancel Job`
- `Open Project`
- `Reveal Output`

Rules:

- each row must make cause and effect obvious
- no row should hide what project or track it belongs to

### 10. Exports

Purpose:

- show what the user has already made and where it went

Buttons:

- `Export Stems`
- `Open Folder`
- `Reveal in Finder`
- `Duplicate Export Settings`
- `Delete Export Record`

Views:

- recent exports
- pending exports
- failed exports

### 11. Models & Storage

Purpose:

- expose desktop-native capability state without making it feel like a dev console

Sections:

- model availability
- cache storage
- library root locations
- diagnostics

Buttons:

- `Download Model`
- `Clear Cache`
- `Open Cache Folder`
- `Move Library Root`
- `Run Diagnostics`

Rules:

- use plain language before technical names
- technical names can appear as secondary detail

### 12. Settings

Desktop settings groups:

- `General`
- `Audio`
- `Files`
- `Shortcuts`
- `About`

Buttons:

- `Check for Updates`
- `Open Logs`
- `Reset Tips`
- `Restore Defaults`

## iOS-Only Screens

### 13. Projects

Purpose:

- touch-first overview of creative work

Content:

- large recent cards
- swipe actions
- pinned current project

Buttons and actions:

- `Open`
- `Rename`
- `Duplicate`
- `Delete`
- swipe `Share`
- swipe `Archive`

Rules:

- one-handed use matters more than data density

### 14. Library

Purpose:

- lightweight local crate for reopening tracks

Buttons:

- `Add from Files`
- `Create Project`
- `Open in Splitter`
- `Share Source`
- `Remove`

Rules:

- no folder roots
- no technical cache management
- metadata should stay readable without looking sparse

### 15. Export and Share Sheet

Purpose:

- make project output mobile-native

Buttons:

- `Share`
- `Save to Files`
- `Open In`
- `Cancel`

Export options:

- stem pack
- selected stem

### 16. Settings

iOS settings groups:

- `General`
- `Storage`
- `About`

Buttons:

- `Clear Cached Audio`
- `Reset Onboarding`
- `Open Privacy Summary`

Rules:

- fewer surfaces than desktop
- no fake parity for desktop-only features

## Global Dialogs and Secondary Surfaces

These are required for polish because indie apps win on secondary moments:

- `Rename Project`
- `Delete Project`
- `Archive Project`
- `Export Setup`
- `Missing Model`
- `Import Conflict`
- `Analysis Failed`
- `Clear Cache`
- `Remove from Library`
- `Unsaved Work` if needed

Each dialog should have:

- one clear primary action
- one safe cancellation path
- short explanation text
- no vague confirm labels like `OK`

## State Requirements

Every major screen must support:

- empty
- loading
- populated
- error

Additional state requirements:

- long filenames
- duplicate project names
- deleted or moved source files
- missing high-quality model
- queue interrupted during app close
- export failure
- partially analyzed project

## Interaction Rules

### Desktop

- keyboard navigation must feel intentional, not bolted on
- command palette is always available with `Cmd+K`
- drag and drop should work from Finder into Home, Projects, and Library
- sidebar should support compact and expanded width

### iOS

- primary actions must be thumb-reachable
- destructive actions should prefer swipe-confirm or sheets over tiny inline buttons
- share flows should use system-native affordances

## Visual Direction

Recommended design DNA: **Editorial product shell with restrained technical detail**

Why:

- it preserves Stemacle’s quiet, physical brand
- it avoids collapsing into black-box DJ software or AI dashboard tropes
- it leaves room for the instruments to feel tactile and special

Visual rules:

- warm off-white or bone backgrounds
- deep plum or brown-black ink
- restrained accent use only for active, saved, or warning states
- strong type hierarchy
- minimal decorative lines
- almost no repeated generic cards
- native desktop and iOS views should echo the perfect web app's matte circle, dense stem rows, and restrained physical feel before introducing new structure

Hard rejections:

- purple-on-black AI gradients
- glass panels
- generic side-nav SaaS dashboards
- neon DJ booth aesthetics
- flat app-store-template layouts

## Asset Strategy

Image generation is not the primary tool for designing the app shell.

Use code, layout work, and Figma-like product design workflows for:

- full app screens
- navigation structure
- typography hierarchy
- layout exploration
- production UI states

Use image generation sparingly for:

- small branded assets
- tentacle icons
- organic decorative elements
- splash or loading details
- exploratory motion frames for tiny icon animations

## Visual QA Requirements

The native apps are not ready until the following QA pass is complete.

### Screen-State QA

Check every major screen in:

- empty
- loading
- error
- populated

### Data QA

Test:

- extremely long filenames
- many projects
- zero projects
- one project
- missing models
- failed imports
- stale export paths
- duplicate tracks

### Layout QA

Desktop:

- small laptop width
- standard laptop width
- large desktop
- ultra-wide

iOS:

- iPhone portrait
- iPhone landscape
- iPad portrait
- iPad split or narrow width where applicable

### Interaction QA

Verify:

- hover states desktop only
- focus states
- keyboard navigation
- drag and drop
- sheet and dialog behavior
- reduced-motion behavior
- disabled-state clarity

### Product QA

Confirm:

- native Stem Splitter behavior matches the perfect web app before native-only features are evaluated
- primary action is visible without scrolling on first entry
- every screen answers “what do I do next?”
- Splitter and Shuffle still feel like the heart of the app
- the shell feels like a product, not a long webpage

## Release Scope

## Must Have

- project-centric shell
- home surface
- projects index
- project detail
- embedded splitter
- embedded shuffle
- library
- desktop queue
- exports
- platform-appropriate settings
- polished empty/loading/error states

## Should Have

- command palette desktop
- saved loop ideas
- saved shuffle ideas
- duplicate project
- archive project
- import conflict handling

## Won't Have In This Pass

- full DAW timeline
- collaborative cloud sync
- accounts
- social features
- beat-perfect mobile remix workstation
- fake desktop-only parity that fights iOS touch, Files, share, haptics, and mobile layout strengths

## Success Criteria

This product direction succeeds when:

- `https://stemacle.com/app/` remains untouched and perfect
- `https://ericspencer.us/stem-player` is documented as pointing to the canonical web app
- native desktop and iOS match the web app's splitter controls, loop behavior, and visual hierarchy before adding new features
- users start from `Home` or `Projects`, not from a naked web route
- a project feels like the center of work across both desktop and iOS
- Splitter and Shuffle feel embedded, not wrapped
- desktop clearly owns SwiftUI-native heavy local work
- iOS clearly owns SwiftUI-native touch-first project access, import, sharing, haptics, and mobile polish
- the overall app reads as an intentional indie product rather than a website in a frame
