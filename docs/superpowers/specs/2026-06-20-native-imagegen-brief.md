# Stemacle Native Image Generation And Icon Motion Brief

## Goal

Use image generation **sparingly** for small branded raster assets, especially tentacle marks, tentacle icon variants, and other tiny organic visual elements that are tedious to draw from scratch.

This brief is not for generating full app screens. It is for micro-assets and motion exploration only.

## Core Rule

Do not use image generation as the main design tool for the desktop or iOS app shell.

Use image generation for:

- tentacle logo exploration
- tentacle icon variants
- tiny decorative brand marks
- launch or loading ornaments
- organic motion-frame exploration for small icons

Do not use image generation for:

- desktop `Home`, `Projects`, `Library`, or other full screens
- iPhone screen mockups
- text-heavy UI
- navigation concepts
- production layout work
- anything that should really be SVG, CSS, canvas, or hand-authored product design

## When Image Generation Is Appropriate

Use it when the asset is:

- small
- organic
- brand-adjacent
- easier to explore through visual variation than through precise vector drafting

Stemacle examples:

- tentacle badge icon
- alternate tentacle silhouette for a toolbar icon
- tiny animated tentacle curl for a loading state
- plume or ink-like organic accent near the splash mark

## When It Is The Wrong Tool

Do not use it when the asset is:

- text-dependent
- grid-dependent
- layout-dependent
- expected to be crisp and scalable from the start

If the end result needs precise geometry, prefer:

- SVG
- CSS transform animation
- canvas animation
- hand-authored frame art

## Recommended Use Cases

### 1. Logo And Mark Exploration

Good for:

- trying multiple tentacle silhouettes
- finding a more characterful curl or loop
- exploring personality without redrawing from scratch

### 2. Small UI Embellishments

Good for:

- loading glyphs
- tiny empty-state accents
- stamped micro-illustrations

### 3. Organic Icon Motion Exploration

Good for:

- a tentacle uncurling
- a tentacle rotating from one pose to another
- a soft wiggle between two icon states
- a tiny branded pulse or recoil

This is where frame generation can help.

## Motion Strategy

Yes, image generation can be used to create `frame 1`, `frame 2`, and so on for a small icon animation.

But the right way to do it is **not** “generate 24 unrelated frames and hope they animate.”

The right way is:

1. choose a very small motion idea
2. define start and end poses
3. generate a handful of controlled keyframes
4. clean and normalize them
5. assemble them into a sequence
6. use the sequence directly, or redraw/vectorize the final motion if it needs to be sharper

## Best-Fit Motion Types

Image generation works best for:

- organic wiggles
- curls
- soft squish and stretch
- hand-drawn-feeling pose changes
- living logo behaviors

It works poorly for:

- geometric morphs
- precise icon-to-icon interpolation
- strict UI state transitions
- anything needing pixel-perfect edge consistency out of the model

For strict icon morphs, prefer SVG or code animation. Use image generation only to discover poses or personality.

## Recommended Pipeline

## Pipeline A: Exploratory Raster Frame Sequence

Use this when the animation is decorative, tiny, and allowed to feel slightly hand-made.

### Step 1. Define the motion brief

Write a one-line motion goal:

- “Tentacle icon uncurls slightly and settles”
- “Tentacle badge leans left, then returns to center”
- “Stemacle tentacle opens from compact mark to alert state”

Lock these constraints before generating anything:

- canvas size
- background treatment
- line color
- fill color
- visual weight
- camera angle
- icon scale

For Stemacle, default constraints should be:

- square canvas
- centered icon
- warm cream or chroma-key background
- deep plum linework
- minimal or no shading
- no text

### Step 2. Define the key poses

Do not start by asking for every frame.

Start with:

- `frame-00`: start pose
- `frame-03`: middle pose
- `frame-06`: end pose

Sometimes `00`, `02`, `04`, `06` is enough.

The smaller the animation, the fewer unique poses you need.

### Step 3. Generate key poses one at a time

Generate each frame as a separate image request with the same locked constraints.

Prompt each frame with:

- exact frame number
- total frame count
- what changed from the previous pose
- what must stay fixed

Required invariants:

- same centered composition
- same icon size
- same color palette
- same stroke personality
- same background

### Step 4. Use reference images aggressively

For frame continuity, feed prior frames back in as references when possible.

Practical rule for the agent:

- generate `frame-00`
- generate `frame-03` using `frame-00` as reference
- generate `frame-06` using `frame-03` and `frame-00` as reference
- fill `frame-01`, `frame-02`, `frame-04`, `frame-05` using nearest key poses as references

Do not ask the model for a whole strip or contact sheet unless it is just for planning.

Separate image files are easier to normalize and assemble.

### Step 5. Normalize every frame

After generation, every frame must be normalized before assembly.

Check:

- icon centered consistently
- same pixel dimensions
- same padding
- same palette
- same line weight feel
- same background treatment

If the icon drifts, recrop or recenter it.

If the palette shifts, correct it before continuing.

If the silhouette mutates too much, regenerate that one frame rather than accepting jitter.

### Step 6. Remove the background if needed

If the animation needs transparency:

- generate on a flat chroma-key background
- remove the background after generation
- save transparent PNG frames

This is especially useful for:

- loading icons
- toolbar flourishes
- overlay motion

### Step 7. Assemble the sequence

Once the frames are clean, assemble them into one of:

- APNG
- animated WebP
- GIF for rough preview only
- sprite sheet for CSS `steps()`
- PNG sequence for a canvas or native animation pipeline

Recommended order of preference:

1. PNG sequence for further work
2. animated WebP or APNG for preview
3. sprite sheet if the product implementation wants stepped playback
4. GIF only for quick review

### Step 8. Review at actual icon sizes

Review the motion at:

- `24px`
- `32px`
- `48px`

If it only looks good at 512px, it is not ready.

## Pipeline B: Production-Quality Motion With Manual Cleanup

Use this when the motion needs to ship in a polished product.

Workflow:

1. use image generation to discover 3-7 good poses
2. pick the best poses
3. redraw or trace them into cleaner SVG or crisp raster frames
4. animate the cleaned sequence

This is the better pipeline for:

- toolbar icons
- onboarding micro-animations
- splash mark motion
- any asset that needs long-term maintainability

In other words:

- image generation is the pose-finder
- manual cleanup is the ship vehicle

## Pipeline C: No Image Generation, Just Code Or SVG

Use this instead when the icon motion is:

- geometric
- simple
- strictly state-based
- better described as transform, rotate, fade, mask, or path morph

Examples:

- crossfade between two UI icons
- scale-and-rotate alert badge
- simple open/close chevron-like motion

For those, do not create frames with image generation. Animate directly in code.

## Agent Handoff Instructions

If handing this to another agent, tell them:

1. Image generation is for micro-assets only.
2. Do not use it for full-screen mockups.
3. Pick one icon animation concept at a time.
4. Generate keyframes first, not every frame.
5. Normalize all frames before assembly.
6. Reject any frame that drifts, mutates, or changes palette.
7. If the result is promising but messy, redraw or trace it instead of endlessly regenerating.

## Suggested Directory Structure

Use a structure like this for one motion study:

```text
tmp/imagegen/tentacle-wiggle-v1/
  prompts/
    frame-00.txt
    frame-03.txt
    frame-06.txt
  raw/
    frame-00.png
    frame-01.png
    frame-02.png
    frame-03.png
    frame-04.png
    frame-05.png
    frame-06.png
  clean/
    frame-00.png
    frame-01.png
    frame-02.png
    frame-03.png
    frame-04.png
    frame-05.png
    frame-06.png
  previews/
    tentacle-wiggle.webp
    tentacle-wiggle.apng
    tentacle-wiggle.gif
```

If the asset is approved, move the final result into the workspace under a real asset path.

## Prompting Rules For Icon Frames

Every prompt should explicitly lock:

- same icon character
- same centered composition
- same canvas size
- same background
- same palette
- same line weight
- no text
- no extra decorative objects

Use prompts like:

```text
Use case: logo-brand
Asset type: tiny animated icon frame
Primary request: frame 03 of 06 for a Stemacle tentacle icon animation
Subject: the same single tentacle logo mark as prior frames, centered on canvas
Style: minimal matte brand icon, deep plum linework, warm cream background, organic but clean
Composition: centered, same scale and crop as previous frame
Motion note: this frame is the midpoint of a gentle uncurl from compact to slightly open
Constraints: preserve the same icon identity, silhouette family, palette, and line weight; no text; no extra elements
Avoid: full illustration, gradients, realistic shading, multiple tentacles, background texture, composition drift
```

For transparent output exploration:

```text
Create the same icon on a perfectly flat solid chroma-key background for later background removal.
The background must be one uniform color with no gradients, no shadows, and no texture.
```

## Assembly Commands

These commands are useful after the frames are cleaned.

Animated WebP preview:

```bash
ffmpeg -framerate 12 -i clean/frame-%02d.png -loop 0 previews/tentacle-wiggle.webp
```

GIF preview:

```bash
ffmpeg -framerate 12 -i clean/frame-%02d.png -vf "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" previews/tentacle-wiggle.gif
```

APNG preview:

```bash
ffmpeg -framerate 12 -i clean/frame-%02d.png -plays 0 previews/tentacle-wiggle.apng
```

Sprite sheet:

```bash
ffmpeg -i clean/frame-%02d.png -filter_complex "tile=7x1" previews/tentacle-wiggle-strip.png
```

## Acceptance Criteria

The animation study is acceptable only if:

- the icon identity stays consistent across frames
- there is no obvious frame-to-frame jump unless intentionally snappy
- the icon remains centered
- the motion reads clearly at small UI sizes
- the palette does not drift
- the result still feels like Stemacle, not a random mascot

Reject the study if:

- frames look like different characters
- composition wanders
- line weight changes wildly
- the motion is only readable at large size
- the animation looks noisy or AI-generated in a distracting way

## Recommended Agent Decision Tree

Ask the agent to decide like this:

1. Is this a full-screen UI problem?
   - If yes, do not use image generation.
2. Is this a tiny branded organic asset?
   - If yes, image generation may help.
3. Is the motion geometric and strict?
   - If yes, use SVG or code animation instead.
4. Is the motion organic and small?
   - If yes, use keyframe generation plus cleanup.
5. Does the generated sequence still look unstable?
   - If yes, stop generating and redraw the chosen poses manually.

## Bottom Line

For Stemacle, image generation should be a **small sharp tool**, not a default workflow.

Use it where it is genuinely strong:

- tentacle marks
- tiny decorative brand elements
- exploratory organic icon motion

Keep it out of:

- core product layout
- main UI structure
- anything that depends on precision more than personality
