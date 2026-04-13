# Jarvina Live Regression Checklist

## Scope
Manual regression checklist for Jarvina Live core flow:
- authentication and access gate
- mic preview
- WebSocket live connection
- audio send path
- audio return path
- live session shutdown

## Preconditions
1. Local server is running and Jarvina page is reachable.
2. Browser mic permission is enabled for the page origin.
3. Network can reach `wss://jarvina-production.up.railway.app/ws/live`.
4. Test user has valid admin session/token when required.

## Regression Cases

| ID | Area | Steps | Expected Result |
|---|---|---|---|
| R-01 | Authentication | Open `jarvina.php` without valid admin session/token. | Access is blocked (redirect/login/forbidden). No live session starts. |
| R-02 | Authentication | Open Jarvina with valid admin session/token. | Page loads and live button is visible. |
| R-03 | Mic Preview | Open Jarvina page and grant mic permission when prompted. Speak near mic. | Status changes to mic ready, VU meter reacts, mic indicator turns on while speaking. |
| R-04 | Mic Preview | Deny mic permission. | Clear failure message is shown and live flow does not silently continue. |
| R-05 | WS Connection | Click `CONEXAO LIVE`. | UI changes to online/live state and no immediate disconnect occurs. |
| R-06 | Audio Send | While live, speak for 5-10 seconds and observe network/dev logs. | Outbound audio chunks are sent continuously (`audio/pcm;rate=<captura_atual>`), sem travar em taxa fixa incorreta. |
| R-07 | Audio Return | After speaking and short pause, listen for model answer. | Audio response is played and/or text feedback is rendered in UI. |
| R-08 | End Of Turn | Speak in short sentence and pause. | End-of-turn event is sent after speech stop (no spam when silent). |
| R-09 | Shutdown | Click `ENCERRAR`. | WS connection closes, UI returns to standby/mic preview mode, no more outbound chunks. |
| R-10 | Reconnect | Start live again after shutdown. | Reconnect succeeds and flow works again without page refresh. |

## Evidence To Capture
1. Screenshot or recording for R-03, R-05, R-09.
2. Browser console/network logs for R-06, R-08.
3. Timestamped run result from `checks/smoke-local.ps1`.

## Exit Criteria
Regression is green when:
1. R-01 through R-10 pass.
2. Smoke script returns exit code `0`.
3. No blocking error appears in browser console during live cycle.
