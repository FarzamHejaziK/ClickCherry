---
description: Active unresolved issues with concrete repro details, mitigation, and next actions.
---

# Open Issues

## Issue OI-2026-02-11-007
- Issue ID: OI-2026-02-11-007
- Title: ClickCherry top-bar branding is inconsistent (capsule styling or missing icon/name)
- Status: Open
- Severity: Medium
- First Seen: 2026-02-11
- Scope:
  - Affects window top-bar branding only (titlebar UI/visual identity).
  - Does not block core task creation/execution flows.
- Repro Steps:
  1. Build and run `TaskAgentMacOSApp`.
  2. Open the main app window and inspect top bar near traffic-light controls.
  3. Compare rendering after titlebar-branding implementation changes.
- Observed:
  - SwiftUI title-bar toolbar placements can show an unwanted rounded capsule around `ClickCherry`.
  - AppKit accessory-path attempts can still fail to show icon/name in some local runs.
- Expected:
  - Plain icon (left) + `ClickCherry` text in top bar near traffic lights, with no capsule/border styling.
- Current Mitigation:
  - Issue is intentionally deferred and tracked; no further active implementation work in this step.
  - App remains usable for core task-agent functionality while branding behavior is unresolved.
- Next Action:
  - Revisit with deterministic window-level titlebar integration path and verify on live runtime:
    - install/update titlebar branding at window lifecycle boundary.
    - verify rendering across relaunch/rebuild cycles with manual screenshots.
  - Close only after stable no-capsule rendering is confirmed locally.
- Owner: Codex + user validation in local Xcode runtime

## Issue OI-2026-02-09-006
- Issue ID: OI-2026-02-09-006
- Title: Execution tool_use loops but desktop actions fail (key injection errors and/or coordinate translation)
- Status: Mitigated
- Severity: High
- First Seen: 2026-02-09
- Scope:
  - Affects Step 4 execution agent (Anthropic computer-use tool loop).
  - As of 2026-02-13, v1 UI no longer exposes Anthropic execution provider selection (OpenAI-only), so this does not block v1 runs.
- Repro Steps:
  1. Ensure Anthropic API key is configured.
  2. Click `Run Task` on any task.
  3. Observe `Diagnostics -> Execution Trace`.
- Observed:
  - Previously observed: `computer.key("cmd+space")` failed with a non-actionable `DesktopActionExecutorError` (AppleScript `System Events` path).
  - Some runs included tool actions like `scroll` that were not yet implemented, causing repeated unsupported-action loops.
  - Some runs included `cursor_position` before local support existed, causing unsupported-action loops.
  - Screenshot capture succeeds.
- Expected:
  - Tool uses should map cleanly to local actions (key/click/type/open) and produce visible progress.
- Current Mitigation:
  - Execution Trace is available in-app so failures are visible.
  - `Stop` button can cancel runaway tool loops.
  - Shortcut + typing injection now use CGEvent-based injection (AppleScript `System Events` path removed, so Automation permission is no longer required).
  - `scroll` and `cursor_position` actions are now supported in the tool loop (covered by unit tests). Manual live-flow verification pending.
  - Tool-loop requests now keep full text/tool history but retain only the latest screenshot image block, reducing payload growth during long runs.
  - Screenshot encoding now enforces Anthropic's 5 MB limit on base64 payload size (prevents raw-bytes-under-limit/base64-over-limit request failures).
  - Runtime terminal policy now rejects visual/UI-oriented terminal commands and directs model behavior to the `computer` tool.
  - Execution provider selection UI is OpenAI-only, so Anthropic runs are not reachable in v1 UX.
- Next Action:
  - If Anthropic execution is reintroduced, validate coordinate translation between Anthropic screenshot coordinates and macOS `CGEvent` coordinates (Retina logical vs capture pixels and origin/space).
- Owner: Codex

## Issue OI-2026-02-09-005
- Issue ID: OI-2026-02-09-005
- Title: Intermittent Anthropic TLS failure (-1200 / errSSLPeerBadRecordMac -9820) during computer-use runs
- Status: Mitigated
- Severity: Medium
- First Seen: 2026-02-09
- Scope:
  - Affects Anthropic execution-agent calls to `https://api.anthropic.com/v1/messages`.
  - Manifests as transient TLS failures from `URLSession` with `NSURLErrorDomain code=-1200` and stream error `-9820`.
- Repro Steps:
  1. Run `Run Task` with Anthropic execution enabled.
  2. Observe that some runs fail immediately with TLS error, then later succeed without code changes.
- Observed:
  - Error includes `_kCFStreamErrorCodeKey=-9820` (mapped in Security headers as `errSSLPeerBadRecordMac`).
- Expected:
  - Execution-agent calls should be reliable; transient transport errors should be retried automatically.
- Current Mitigation:
  - Added transport retries with exponential backoff (default 5 attempts) on transient `URLSession` failures including `secureConnectionFailed` (`-1200`) and `networkConnectionLost`.
  - Surfaced detailed transport diagnostics (domain/code + underlying error chain) to aid debugging.
  - Added a temporary in-app `Diagnostics (LLM + Screenshot)` panel that:
    - shows successful + failed LLM calls (attempt number, HTTP status, request-id, duration, error snippet)
    - provides a `Test Screenshot` button with a live screenshot preview for Screen Recording validation
- Next Action:
  - If this continues in user local runtime, investigate per-app proxy/VPN/TLS inspection and consider additional mitigations (fresh session on retry, larger retry budget, or payload size reduction).
- Owner: Codex + user network environment validation

## Issue OI-2026-02-09-004
- Issue ID: OI-2026-02-09-004
- Title: Prompt resource filename collision when adding multiple prompt folders
- Status: Mitigated
- Severity: Low
- First Seen: 2026-02-09
- Scope:
  - Affects adding additional prompt folders that contain the required `prompt.md` and `config.yaml` filenames.
  - Blocks straightforward file-based prompt expansion for execution-agent prompt under current Xcode target configuration.
- Repro Steps:
  1. Add a second folder under `TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/` with files named `prompt.md` and `config.yaml`.
  2. Build or test target `TaskAgentMacOSApp`.
- Observed:
  - Build fails with duplicate resource outputs for `prompt.md` and `config.yaml` in app bundle resource path.
- Expected:
  - Multiple prompt folders with the same internal filenames should be packageable without resource output collisions.
- Current Mitigation:
  - Prompt files (`prompt.md`, `config.yaml`) are excluded from Xcode auto resource copy to avoid flattened-name collisions.
  - Runtime prompt loading uses `PromptCatalogService`, preferring source prompt directories in debug builds.
  - `execution_agent` and `task_extraction` both remain file-based prompt folders.
- Next Action:
  - Add a robust bundle-packaging strategy for production builds so prompt folders can be loaded without relying on source-tree fallback.
- Owner: Codex

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
