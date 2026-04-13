# Jarvina Live Validation Checklist

Use this quick checklist during real-time validation. For full evidence and decision gate, fill a report in `Agentes/Jarvina/reports/`.

- [ ] LV-01 Microphone permission prompt handled and audio capture starts.
- [ ] LV-02 UI status transitions idle -> connecting -> active -> ended.
- [ ] LV-03 WS session remains stable for 10 minutes with intermittent speech.
- [ ] LV-04 mic_debug watchdog detects silence and auto-recovers on resumed speech.
- [ ] LV-05 Session shutdown releases mic, closes WS, and next open starts clean.

If any item fails, mark run as `NO-GO` and open a follow-up issue with timestamped evidence.

