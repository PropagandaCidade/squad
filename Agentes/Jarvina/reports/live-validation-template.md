# Jarvina Live Validation Template

## Objective
Operational live validation of Jarvina voice flow without changing production code.

## Execution Metadata
- Operator: {name}
- Date: {yyyy-mm-dd}
- Environment: {local|staging|prod}
- URL: {target_url}
- Browser: {browser + version}
- Build/Commit: {id}

## Pre-Checks
- [ ] Target URL opens without HTTP errors.
- [ ] Microphone device is available in OS and browser.
- [ ] Browser permission state is known (prompt/allow/block).
- [ ] DevTools console and WS network tab are open.
- [ ] Test window reserved for at least 10 minutes continuous run.

## PASS/FAIL Matrix
| ID | Area | Procedure | PASS Criteria | FAIL Criteria | Result | Evidence |
|---|---|---|---|---|---|---|
| LV-01 | Microphone Permission | Trigger voice start and handle permission prompt. | Prompt + successful capture after allow. | No prompt when expected, blocked flow, or no capture after allow. | {PASS/FAIL/BLOCKED} | {links or notes} |
| LV-02 | UI Status | Observe idle/connect/active/end transitions. | Correct sequence with no stuck state. | Missing transition or stuck status. | {PASS/FAIL/BLOCKED} | {links or notes} |
| LV-03 | WS Connection Stability | 10-minute session with intermittent speech every 20-30s. | Stable WS, no reconnect storm, no long audio gap. | Reconnect loop, dropped session, long interruption. | {PASS/FAIL/BLOCKED} | {links or notes} |
| LV-04 | mic_debug Watchdog | 30s silence then resume speech. | Watchdog detects silence and recovers automatically. | No detection, false-loop alerts, or no recovery. | {PASS/FAIL/BLOCKED} | {links or notes} |
| LV-05 | Session Shutdown | End via UI and close tab. Reopen and verify clean idle state. | Mic released, WS closed, clean restart. | Hanging mic/WS or corrupted next start. | {PASS/FAIL/BLOCKED} | {links or notes} |

## Run Notes
- Start time: {hh:mm}
- End time: {hh:mm}
- Incident timeline:
  - {timestamp} - {event}
  - {timestamp} - {event}
- Additional observations:
  - {note}

## Final Result
- Overall status: {PASS|FAIL|BLOCKED}
- Production recommendation: {GO|NO-GO}
- Open follow-ups:
  - {owner} - {action}

