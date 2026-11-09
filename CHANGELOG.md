# Changelog

Versions follow `vA.B.C` (A: breaking change, B: new feature that may require changes on your side, C: bug fix).

## Unreleased
- Added an English top-level README; the Japanese one moved to `README.ja.md`. This changelog is now in English.
- `MCPSystem/README.md` is now in English (full translation, including the tool table); the Japanese original moved to `MCPSystem/README.ja.md`.

## v0.1.0 (2026-11-09) — UEFN v43.00
- First release (still being organized; the public API may change during 0.x).
- Known issues (real errors reported by the standalone type checker; not yet confirmed in a UEFN build):
  - `CharacterSystem/CharacterMotorComponent.verse`: `MotorLedgeAssistToolTip` is undefined (missing from TooltipKit).
  - `CharacterSystem/CharacterMotorComponent.verse`: `Distance` inside `StopDistance` is ambiguous with `Distance` from `/Verse.org/SpatialMath` (V3532 / V3588).
