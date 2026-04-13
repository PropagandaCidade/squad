# Enterprise Memory Changelog

## 2026-04-12
- Enterprise memory structure initialized for SQUAD.
- Governance, execution, quality, operations, and audit templates prepared.
- Initial working sets and handoff created for multi-agent workflow.
- Runtime heartbeat layer enabled for all 40 agents (`agents-registry.json` + `agent-heartbeats.json`).
- Working sets and profiles auto-scaffolded for all agents, including assistant/volta/bohr/halley.
- Admin page updated to monitor all agent working sets and live execution status.
- Hired agent `Otavio` focused on `QA Zoom Studio Hub` with dedicated runner and test suite.
- Added heartbeat write retry to tolerate concurrent agent updates (runtime file lock hardening).
- Admin page now auto-discovers agents from `runtime/agents-registry.json` (hire/fire reflected without manual edits).
- Root `index.html` now syncs agent headcount from registry and auto-allocates unassigned hires into `Operacoes Especiais`.
- Admin panel now warns when opened via `file://` and includes local server launcher script (`run-admin-memoria-squad.ps1`) for real-time updates.
- Studio Hub Editor Visual hardening completed: wheel zoom recovery, stale drag-lock recovery, anti-duplicate blue needles, and delete/F5 persistence stabilization.
- Added and executed full automated suite for Studio Hub Editor Visual (`studio-hub/tools/editor_visual_master_playwright.js`) with final result `8/8 PASS`.
- Admin realtime panel now reads runtime heartbeat data (`agent-heartbeats.json`) directly for live updates even when only runtime changes.
- Admin panel redesigned as operational realtime dashboard (event feed + per-request monitor + live tasks/agents) and launcher default port aligned to `8094`.
- Dashboard enriched with `Agentes Online + Supervisão + Ação Atual` and realtime progress bars (projeto/correções/atividade/qualidade).
- Studio Master principal synchronized with stable zoom/sfx/ui stack and validated with full Playwright battery (`9/9 PASS`).
