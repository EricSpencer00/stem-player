# Stem Splitting Quality

## Current Splitters

Stemacle now has three quality tiers:

| Surface | Splitter | Expected behavior |
| --- | --- | --- |
| Web app | Browser ONNX 2-stem Spleeter + DSP | Vocals/accompaniment are model-derived when ONNX loads. Drums, bass, and melody are still estimated from accompaniment, so blending is expected on dense mixes. |
| Native Apple on-device | Shared Rust DSP | Fast offline preview. It is deterministic and reconstructs the mix, but it is not a true neural four-stem separator. |
| Server-backed native | Demucs/MDX via `server/app.py` | True four-source separation: `drums`, `bass`, `other` mapped to `melody`, and `vocals`. This is the quality path. |

## Public Options Checked

| Model family | Status for Stemacle | Notes |
| --- | --- | --- |
| Demucs `htdemucs` | Default server model | Public four-stem model; produces the actual Stemacle stem set. |
| Demucs `htdemucs_ft` | Exposed in Apple settings | Fine-tuned variant; slower, usually cleaner. |
| Demucs `mdx_extra` | Exposed in Apple settings | Alternate public MDX model available through Demucs. Use it as a quick A/B path when `htdemucs` blends too much. |
| Spleeter | Browser compatibility path | Public and easy to run as ONNX, but the current browser package is 2-stem, so four-control output is partly heuristic. |
| Open-Unmix | Candidate fallback | Public four-stem PyTorch baseline. Keep as a fallback candidate if Demucs packaging becomes a problem. |

## Guardrails Added

- The shared Rust fallback now gates its vocal mask to the vocal band, so centered sub-bass no longer lands in the vocal stem.
- Browser fallback and browser ONNX mask code use the same vocal-band gate.
- Apple settings expose every model accepted by the queue server: `htdemucs`, `htdemucs_ft`, and `mdx_extra`.
- Apple library metadata records the selected server model instead of flattening every server split to `htdemucs`.

## Next A/B Test

For a real song that sounds blended, run the same input through:

1. `htdemucs`
2. `htdemucs_ft`
3. `mdx_extra`

Compare vocal bleed in bass/drums, bass bleed in vocals, and transient smear in drums. If one model clearly wins on common user material, make that the recommended server default while keeping the others selectable.
