# Stemacle Release Downloads Design

## Goal

Ship Stemacle as a real downloadable SwiftUI desktop product with durable GitHub Release assets and a landing page that sends users to the correct public release path instead of hardcoded one-off version links.

`https://stemacle.com/app/` remains the perfect canonical web app. `https://ericspencer.us/stem-player` points to it. Release work must preserve that contract and must not present the legacy URL as a separate app.

This slice covers:

- desktop release automation
- public release asset naming
- landing-page download behavior
- GitHub Actions packaging and release publication

It does not redefine the web app or expand the product away from the SwiftUI desktop direction.

## Approaches Considered

### 1. Recommended: GitHub Release as the public download source

Build platform installers in GitHub Actions, upload them to a tagged GitHub Release, and have `stemacle.com` point at durable `releases/latest/download/...` asset URLs.

Why this wins:

- durable public URLs
- no extra storage or CDN system
- simple mental model for the site and for releases
- works with the existing static Pages deployment

### 2. Manual release uploads with the current validation workflow

Keep validating builds in CI but rely on manual local packaging and asset uploads.

Why not:

- too easy for the site to advertise files that were never uploaded
- inconsistent file naming
- not end-to-end

### 3. Separate hosted artifact storage

Publish binaries somewhere other than GitHub Releases and let the site download from there.

Why not:

- adds infrastructure before it is needed
- slower to ship
- no clear product benefit right now

## Chosen Direction

Adopt approach 1.

Stemacle should publish desktop installers directly from GitHub Actions into GitHub Releases, then let the landing page link to those stable public release assets.

## Release Contract

Every public desktop release should produce the current SwiftUI desktop asset:

- `Stemacle-mac-arm64.zip`

Compatibility assets may still exist, but they must not redefine the desktop product direction away from SwiftUI parity-plus.

## Workflow Architecture

### Validation workflow

Keep the existing validation workflow focused on:

- install
- tests
- site bundle preparation
- native bundle preparation

This remains the fast feedback path for pushes and pull requests.

### Release workflow

Add a separate release workflow that:

- runs on tag push matching `v*`
- can also run manually with `workflow_dispatch`
- verifies the app before packaging
- builds desktop artifacts on platform-appropriate runners
- normalizes public asset names
- uploads the final files to a GitHub Release

### Platform build split

Use a matrix split by operating system:

- macOS runner builds the SwiftUI desktop artifact

This keeps the public desktop product tied to the SwiftUI build instead of the older Electron desktop wrapper.

## Public Asset Naming

Public asset names must be stable across releases.

Reason:

- the landing page can use `releases/latest/download/<filename>`
- download buttons do not need to be rewritten for each version
- the site behaves more like a product page and less like a changelog

The release tag still carries the version. The asset filenames stay stable.

## Landing Page Behavior

The homepage should behave like a product download page:

- the primary desktop CTA changes based on the visitor platform when detectable
- macOS users see the SwiftUI desktop CTA
- unsupported or unknown platforms fall back to the GitHub Releases page
- the web app CTA remains `https://stemacle.com/app/`
- the legacy `ericspencer.us/stem-player` URL is documented as pointing to `https://stemacle.com/app/`

The release manifest section should also list the public download files directly:

- SwiftUI desktop
- GitHub Release page

The site copy should reflect that downloads are live and durable, not placeholders.

## Download Routing Rules

### Primary CTA

Platform detection is best-effort only:

- macOS Apple Silicon defaults to `Stemacle-mac-arm64.zip`

If platform detection is uncertain, route to the GitHub Release page instead of guessing badly.

### Manifest links

Manifest links should stay explicit and stable so users can choose another platform manually.

## Site Build Requirements

The static site build should continue copying the current landing page and app routes into `dist/site`.

No server-side release lookup is required for this pass.

## Error Handling

- If a release asset is missing, the landing page fallback target should still be the GitHub Releases page.
- Release publication should fail loudly if an expected public file is missing after packaging.
- Validation and release workflows should stay separate so normal PR feedback does not wait on full multi-OS packaging.

## Testing

Automated coverage should verify:

- homepage copy and links reference the stable public asset names
- platform-aware CTA wiring exists for macOS, Windows, Linux, and fallback
- release workflow exists and uploads the expected public filenames
- validation workflow still prepares site and native bundles

Manual verification should cover:

- `npm test`
- `npm run site:prepare`
- `npm run native:prepare`
- local desktop packaging on the current machine
- a browser pass on the landing page download section

## Success Criteria

This slice succeeds when:

- Stemacle can publish durable desktop installers from GitHub Actions to GitHub Releases
- the landing page points to stable public release download URLs
- the homepage download CTA feels like a real product download flow
- the perfect web app and legacy redirect contract remain explicit
- the SwiftUI desktop packaging path passes validation
