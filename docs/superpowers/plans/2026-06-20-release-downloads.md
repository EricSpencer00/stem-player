# Stemacle Release Downloads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish durable SwiftUI Stemacle desktop releases to GitHub Releases and make the landing page preserve the perfect web app while exposing the real native download path.

**Architecture:** Keep validation and release responsibilities separate. Let the SwiftUI desktop package produce the public artifact, let a dedicated GitHub Actions workflow build and publish it, and let the static homepage point at `releases/latest/download/...` URLs while keeping `https://stemacle.com/app/` as the perfect canonical web app.

**Tech Stack:** SwiftUI, SwiftPM, Node.js scripts, GitHub Actions, static HTML/CSS/JS, Node test runner

## Global Constraints

- Every public desktop release should produce the SwiftUI desktop asset: `Stemacle-mac-arm64.zip`.
- `https://stemacle.com/app/` is the perfect canonical web app.
- `https://ericspencer.us/stem-player` points to `https://stemacle.com/app/`.
- The landing page can use `releases/latest/download/<filename>`.
- The release tag still carries the version. The asset filenames stay stable.
- Validation and release workflows should stay separate so normal PR feedback does not wait on full multi-OS packaging.
- The primary desktop CTA should not obscure the web app CTA.
- If platform detection is uncertain, route to the GitHub Release page instead of guessing badly.

---

### Task 1: Lock the public SwiftUI desktop release contract into tests and build config

**Files:**
- Modify: `tests/stem-player.test.mjs`
- Modify: `package.json`
- Modify: `scripts/package-macos.mjs`

**Interfaces:**
- Consumes: existing homepage markup, SwiftUI package scripts, and Mac wrapper script.
- Produces: stable artifact-name contract for the SwiftUI desktop build.

- [ ] **Step 1: Write the failing test**

```js
test('desktop packaging uses the stable public SwiftUI artifact name', () => {
  const pkg = loadPackageJson();
  const packageScript = readRepo('scripts/package-macos.mjs');

  assert.equal(pkg.scripts['macos:package'], 'npm run macos:build && node scripts/package-macos.mjs');
  assert.match(packageScript, /Stemacle-mac-arm64\.zip/);
  assert.doesNotMatch(packageScript, /Stemacle-mac-x64/);
  assert.doesNotMatch(packageScript, /\.dmg/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- --test-name-pattern "stable public SwiftUI artifact name"`
Expected: FAIL because the SwiftUI package script or public zip name is not configured yet.

- [ ] **Step 3: Write minimal implementation**

Ensure `package.json` routes `macos:package` through the SwiftUI build and `scripts/package-macos.mjs` writes `Stemacle-mac-arm64.zip`.

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- --test-name-pattern "stable public SwiftUI artifact name"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/stem-player.test.mjs package.json scripts/package-macos.mjs
git commit -m "test: lock stable SwiftUI desktop artifact"
```

### Task 2: Add a dedicated SwiftUI desktop GitHub Release workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `tests/stem-player.test.mjs`

**Interfaces:**
- Consumes: `npm ci`, `npm test`, `npm run native:prepare`, and `npm run macos:package`
- Produces: tagged release workflow that uploads the stable SwiftUI desktop asset

- [ ] **Step 1: Write the failing test**

```js
test('release workflow publishes the durable SwiftUI desktop asset to GitHub Releases', () => {
  const workflow = readFileSync(new URL('../.github/workflows/release.yml', import.meta.url), 'utf8');

  assert.match(workflow, /^name: Release$/m);
  assert.match(workflow, /tags:\s*\n\s*-\s*'v\*'/m);
  assert.match(workflow, /macos-latest/);
  assert.match(workflow, /npm run macos:package/);
  assert.match(workflow, /Stemacle-mac-arm64\.zip/);
  assert.match(workflow, /stemacle\.com\/app/);
  assert.match(workflow, /ericspencer\.us\/stem-player/);
  assert.doesNotMatch(workflow, /Stemacle-mac-x64\.dmg/);
  assert.doesNotMatch(workflow, /electron-builder --publish never --mac/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- --test-name-pattern "release workflow publishes the durable SwiftUI desktop asset"`
Expected: FAIL because the workflow does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```yaml
name: Release
on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
jobs:
  release:
    runs-on: macos-latest
    steps:
      - run: npm run macos:package
```

Upload `release/Stemacle-mac-arm64.zip` to the tagged GitHub Release and keep the web-app/redirect contract visible in workflow comments or checks.

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- --test-name-pattern "release workflow publishes the durable SwiftUI desktop asset"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml tests/stem-player.test.mjs
git commit -m "feat: add SwiftUI desktop release workflow"
```

### Task 3: Turn the homepage into a durable product download surface

**Files:**
- Modify: `index.html`
- Modify: `tests/stem-player.test.mjs`

**Interfaces:**
- Consumes: stable public release asset name, canonical web app URL, redirect contract, and GitHub Releases latest-download URL
- Produces: primary web CTA preservation, SwiftUI desktop download link, and release-page fallback behavior

- [ ] **Step 1: Write the failing test**

```js
test('landing page routes download CTA and manifest to durable latest release assets', () => {
  const html = loadLandingHtml();

  assert.match(html, /href="https:\/\/stemacle\.com\/app\/?"/);
  assert.match(html, /ericspencer\.us\/stem-player/);
  assert.match(html, /id="downloadCta"/);
  assert.match(html, /releases\/latest\/download\/Stemacle-mac-arm64\.zip/);
  assert.match(html, /navigator\.userAgent/);
  assert.doesNotMatch(html, /Stemacle-mac-x64/);
  assert.doesNotMatch(html, /Stemacle-mac-arm64\.dmg/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- --test-name-pattern "landing page routes download CTA and manifest to durable latest release assets"`
Expected: FAIL because the page still hardcodes versioned URLs, old desktop artifacts, or hides the canonical web app.

- [ ] **Step 3: Write minimal implementation**

```html
<a class="cta primary" href="https://stemacle.com/app/">open web app</a>
<a class="cta" id="downloadCta" href="https://github.com/EricSpencer00/stem-player/releases/latest/download/Stemacle-mac-arm64.zip">download SwiftUI desktop</a>
<script>
  const links = {
    macArm: 'https://github.com/EricSpencer00/stem-player/releases/latest/download/Stemacle-mac-arm64.zip',
    releases: 'https://github.com/EricSpencer00/stem-player/releases/latest'
  };
</script>
```

Update the release manifest rows and copy so the web app is canonical and the desktop artifact is clearly SwiftUI.

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- --test-name-pattern "landing page routes download CTA and manifest to durable latest release assets|landing page exposes current web, repo, and GitHub download links"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add index.html tests/stem-player.test.mjs
git commit -m "feat: ship durable homepage download surface"
```

### Task 4: Verify site output, desktop packaging, and visual QA readiness

**Files:**
- Modify: `docs/STEMACLE_SURFACES.md`
- Modify: `docs/superpowers/specs/2026-06-20-release-downloads-design.md`

**Interfaces:**
- Consumes: completed release workflow, landing page download behavior, existing site/native prep scripts
- Produces: updated docs plus verification evidence for release/download behavior

- [ ] **Step 1: Update docs to match shipped release behavior**

```md
Desktop downloads on stemacle.com point at durable GitHub Release assets using stable latest-download filenames.
```

- [ ] **Step 2: Run verification commands**

Run:

```bash
npm test
npm run site:prepare
npm run native:prepare
npm run desktop:pack
```

Expected:

- `npm test` reports 0 failures
- `npm run site:prepare` writes `dist/site`
- `npm run native:prepare` writes `dist/native`
- `npm run desktop:pack` exits 0 on the current machine

- [ ] **Step 3: Run a browser pass on the landing page**

Open the local site and verify:

- primary CTA label is platform-appropriate
- manifest rows expose all supported platforms
- download links point at durable GitHub Release URLs

- [ ] **Step 4: Commit**

```bash
git add docs/STEMACLE_SURFACES.md docs/superpowers/specs/2026-06-20-release-downloads-design.md
git commit -m "docs: align release download contract"
```
