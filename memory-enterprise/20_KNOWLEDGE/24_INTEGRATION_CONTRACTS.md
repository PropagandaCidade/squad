# Integration Contracts

## Contract: SFX State
- Input: `window.programmedSfx` list with stable `id`.
- Output: persisted `studio_programmed_sfx` in local storage.
- Guarantees:
  - delete means deleted after reload;
  - existing non-deleted effect survives reload.

## Contract: SFX Drag
- At most one visual marker per `data-id` during and after drag.
