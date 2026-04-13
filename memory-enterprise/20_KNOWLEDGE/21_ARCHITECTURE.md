# Architecture Notes

## System Overview
- Core UI with waveform, zoom, drag, and SFX overlays.
- State source of truth for SFX persistence.
- Playwright-based regression pipeline.

## Critical Paths
- Wheel -> Zoom -> Ruler sync -> SFX visual sync.
- SFX drag -> state update -> render refresh -> persistence.
