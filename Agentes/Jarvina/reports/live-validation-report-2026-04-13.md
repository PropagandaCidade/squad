# Jarvina Live Validation Report - 2026-04-13

## Objective
Consolidate the official Jarvina `full-live` validation using local PHP runtime + Railway WS path.

## Execution Metadata
- Operator: Jarvina runner
- Date: 2026-04-13
- Time (BRT): 15:08:54
- Environment: Local PHP runtime + Railway production WS
- Base URL: `http://127.0.0.1:8095`
- WS URL: `wss://jarvina-production.up.railway.app/ws/live`
- Command:
  `powershell -ExecutionPolicy Bypass -File .\Agentes\Jarvina\runner\Jarvina.ps1 -Suite full-live -BaseUrl "http://127.0.0.1:8095" -BypassProxy -ReceiveTimeoutSec 20`

## Suite Result (Official Runner)
- Overall status: **PASS**
- Runner output: `[DONE] Jarvina runner finalizado com sucesso.`

### Stage 1: smoke-local
- Result: PASS
- Evidence: `15 passed, 0 failed`
- Key checks:
  - `jarvina.php` and `templates/index.php` auth gate returned allowed `403` without session.
  - Core JS assets returned `200`.
  - `main.js` and `gemini-client.js` required live markers present.

### Stage 2: ws-connect
- Result: PASS
- Evidence:
  - TCP 443 preflight: OK
  - HTTPS preflight: `200`
  - WS opened and setup token sent
  - Warning expected in no-greeting mode:
    `Nenhuma mensagem recebida dentro do timeout; conexao WS e setup estao OK.`

### Stage 3: ws-audio-probe
- Result: PASS
- Evidence:
  - `mic_debug chunks=1 bytes=28800`
  - Model content observed in same session
  - Welcome optional and not required:
    `No welcome message received (optional).`

## Final Decision
- Technical gate: **PASS**
- Live backend receive path: **CONFIRMED**
- Model response path: **CONFIRMED**
- Production recommendation: **GO**

## Notes
- `ws-connect` was updated to support `-BypassProxy` and no longer fail when greeting is intentionally disabled.
- This report supersedes earlier pending status on 2026-04-13.
