# Jarvina Tests

## Quick Run
1. Ensure local server is running (recommended for PHP runtime: `http://127.0.0.1:8095`).
2. Run smoke checks:

```powershell
cd Agentes/Jarvina
powershell -ExecutionPolicy Bypass -File .\checks\smoke-local.ps1
```

3. Optional custom base URL/path:

```powershell
powershell -ExecutionPolicy Bypass -File .\checks\smoke-local.ps1 -BaseUrl "http://127.0.0.1:8095" -JarvinaPath "/Agentes/Jarvina"
```

4. If you are using a static server (for example `python -m http.server`) and only want structural checks, allow static PHP:

```powershell
powershell -ExecutionPolicy Bypass -File .\checks\smoke-local.ps1 -AllowStaticPhp
```

## Railway Audio Probe (WS)
Use this when you need to confirm the browser audio path is reaching Railway backend:

```powershell
cd Agentes/Jarvina
powershell -ExecutionPolicy Bypass -File .\checks\ws-audio-probe.ps1
```

Optional custom endpoint/token:

```powershell
powershell -ExecutionPolicy Bypass -File .\checks\ws-audio-probe.ps1 -WsUrl "wss://jarvina-production.up.railway.app/ws/live" -AdminToken "1"
```

If your machine uses a restrictive proxy policy, try:

```powershell
powershell -ExecutionPolicy Bypass -File .\checks\ws-audio-probe.ps1 -BypassProxy
```

## Manual Regression
Use this checklist for live flow validation:
- `tests/Jarvina-live-regression-checklist.md`

## Agent Runner
Run the official Jarvina runner with heartbeat + gamification:

```powershell
cd Agentes/Jarvina
powershell -ExecutionPolicy Bypass -File .\runner\Jarvina.ps1 -Suite full-live
```
For the current validated environment:

```powershell
powershell -ExecutionPolicy Bypass -File .\runner\Jarvina.ps1 -Suite full-live -BaseUrl "http://127.0.0.1:8095" -BypassProxy
```

Available suites:
- `smoke-local`
- `ws-connect`
- `ws-audio-probe`
- `full-live`

## Exit Codes
- `0`: smoke checks passed
- `1`: one or more checks failed
