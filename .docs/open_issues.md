---
description: Active unresolved issues with concrete repro details, mitigation, and next actions.
---

# Open Issues

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
  - Deferred while Step 3 extraction baseline is implemented.
  - Keep mitigation (`System Default Microphone`) and resume diagnostics after Step 3.2 if still needed.
- Owner: Codex + user validation in local Xcode runtime

# Closed Issues

- None yet.
