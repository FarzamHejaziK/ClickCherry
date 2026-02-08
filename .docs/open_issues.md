---
description: Active unresolved issues with concrete repro details, mitigation, and next actions.
---

# Open Issues

## Issue OI-2026-02-08-003
- Issue ID: OI-2026-02-08-003
- Title: Step 4 clarification UI local verification deferred
- Status: Open
- Severity: Medium
- First Seen: 2026-02-08
- Scope:
  - Affects local UI verification for clarification-answer persistence in `HEARTBEAT.md`.
  - Step 4 code is implemented, but final manual validation cycle is intentionally deferred.
- Repro Steps:
  1. Open a task that has unresolved items in `## Questions`.
  2. Answer one question from the in-app `Clarifications` panel and click `Apply Answer`.
  3. Reopen the task or relaunch the app.
- Observed:
  - This verification run is intentionally deferred for now; no local runtime pass/fail evidence recorded yet.
- Expected:
  - `HEARTBEAT.md` is updated with `- [x] <question>` and `Answer: <answer>`.
  - Resolved state persists after task reopen and app relaunch.
- Current Mitigation:
  - Keep existing clarification parser/apply implementation and tests in place.
  - Continue delivery with Step 4 execution-agent baseline while this manual verification remains tracked.
- Next Action:
  - Run deferred local UI verification after Step 4 execution-agent baseline is implemented.
  - Close issue if persistence behavior is confirmed.
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
  - Keep mitigation (`System Default Microphone`) while Step 4 execution-agent baseline ships.
  - Resume mic diagnostics after Step 4 baseline is stable.
- Owner: Codex + user validation in local Xcode runtime

# Closed Issues

## Issue OI-2026-02-08-002
- Issue ID: OI-2026-02-08-002
- Title: Gemini extraction fails when file poll endpoint returns top-level file object
- Status: Closed
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
  - None.
- Owner: Codex + user validation in local Xcode runtime
- Resolution Date: 2026-02-08
- Resolution Summary: Local user validation confirmed extraction now works end-to-end after parser fix; issue closed.
