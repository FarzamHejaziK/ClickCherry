---
description: Active unresolved issues with concrete repro details, mitigation, and next actions.
---

# Open Issues

## Issue OI-2026-02-08-002
- Issue ID: OI-2026-02-08-002
- Title: Gemini extraction fails when file poll endpoint returns top-level file object
- Status: Mitigated
- Severity: High
- First Seen: 2026-02-08
- Scope:
  - Affects task extraction for recordings after upload completes.
  - Error shown in UI: `Gemini file poll response was invalid.`
- Repro Steps:
  1. Open a task with a valid recording.
  2. Click `Extract Task`.
  3. Observe extraction failure after upload stage.
- Observed:
  - Poll response parsing expected only `{ "file": { ... } }` shape.
  - Some Gemini poll responses return top-level file object `{ "name": ..., "state": ... }`.
- Expected:
  - Poll parser should accept both envelope and top-level file response shapes.
  - Extraction should continue when file state becomes `ACTIVE`.
- Current Mitigation:
  - Parser updated to accept both poll response formats.
  - Added test coverage using top-level poll response shape.
- Next Action:
  - Validate with real app run (`Extract Task`) and close issue after successful extraction.
- Owner: Codex + user validation in local Xcode runtime

## Issue OI-2026-02-07-001
- Issue ID: OI-2026-02-07-001
- Title: Explicit microphone device selection fails and falls back to system default mic
- Status: Open
- Severity: Medium
- First Seen: 2026-02-07
- Scope:
  - Affects explicit microphone selection in task recording UI.
  - Recording still works when fallback uses `System Default Microphone`.
- Repro Steps:
  1. Open `TaskAgentMacOSApp` from Xcode.
  2. Choose any explicit microphone from the `Microphone` picker (not `System Default Microphone`).
  3. Click `Start Capture`, then `Stop Capture`.
- Observed:
  - App reports selected mic is unavailable and falls back to default mic.
  - In some attempts, `screencapture` reports device lookup failure.
- Expected:
  - Selected explicit microphone should be used directly when available.
  - No fallback warning when the selected device is valid.
- Current Mitigation:
  - Use `System Default Microphone`; recording remains functional.
- Next Action:
  - Deferred while Step 3 task extraction baseline is implemented.
  - Keep mitigation (`System Default Microphone`) and resume diagnostics after extraction baseline is stable.
- Owner: Codex + user validation in local Xcode runtime

# Closed Issues

- None yet.
