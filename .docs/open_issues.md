---
description: Active unresolved issues with concrete repro details, mitigation, and next actions.
---

# Open Issues

## Issue OI-2026-02-19-012
- Issue ID: OI-2026-02-19-012
- Title: App aborts when stopping recording and presenting recording-finished preview sheet
- Status: Mitigated
- Severity: High
- First Seen: 2026-02-19
- Scope:
  - Affects the post-recording flow after `New Task` capture stop.
  - Crash appears during recording-finished sheet presentation with AVKit/SwiftUI preview initialization.
- Repro Steps:
  1. Start a recording from `New Task`.
  2. Stop recording (Stop button or Escape path that reaches finished-recording sheet).
  3. Observe app termination while the recording review sheet is being presented.
- Observed:
  - App exits with `EXC_CRASH (SIGABRT)` and `abort() called`.
  - Crash stack contains `_AVKit_SwiftUI`, `PlatformViewRepresentable._makeView`, and Swift metadata fatal paths (`swift::fatalError`, `getSuperclassMetadata`).
- Expected:
  - Stopping recording should reliably present the review sheet with preview and never crash.
- Current Mitigation:
  - Replaced SwiftUI `VideoPlayer` in the recording-finished sheet with a native `AVPlayerView` (`NSViewRepresentable`) wrapper.
  - Deferred `AVPlayer` creation slightly after sheet appearance to avoid stop->restore->sheet presentation timing races.
  - Removed `ProgressView.controlSize(.large)` in this sheet overlay path to reduce associated metadata specialization churn in the crash-prone render path.
- Next Action:
  - User-side runtime validation on local and secondary devices:
    - start recording -> stop recording -> confirm sheet opens and preview renders without crash.
    - repeat at least 10 times, including rapid short captures (<2s).
  - If any crash remains, capture the new crash report and symbolicate against the matching build dSYM.
- Owner: Codex + user validation in local runtime

## Issue OI-2026-02-18-011
- Issue ID: OI-2026-02-18-011
- Title: Release notarization step can fail after long wait due transient runner network loss (`NSURLErrorDomain -1009`)
- Status: Mitigated
- Severity: Medium
- First Seen: 2026-02-18
- Scope:
  - Affects GitHub `Release` workflow notarization wait path.
  - Can fail signed release publishing even after successful upload to Apple Notary service.
- Repro Steps:
  1. Trigger release workflow on tag push (for example `v0.1.6`).
  2. Reach notarization stage with `xcrun notarytool submit ... --wait`.
  3. Observe long-running `In Progress` status.
- Observed:
  - Workflow can hang in long wait and then fail with:
    - `NSURLErrorDomain Code=-1009`
    - `The Internet connection appears to be offline`
  - Failure happens during wait/poll, not submission upload.
- Expected:
  - Transient runner network interruptions should not fail release notarization immediately.
- Current Mitigation:
  - Replaced `notarytool submit --wait` with:
    - submission step that captures submission ID
    - explicit polling step (`notarytool info`) with transient network retry handling
    - bounded wait timeout (90 minutes) and explicit failure path for `Invalid`/`Rejected`.
  - Poll logs now include UTC timestamps and elapsed time so long waits can be attributed to Apple queue time vs retry windows.
- Next Action:
  - Validate in the next release workflow run that transient offline errors retry and recover without failing the job.
- Owner: Codex

## Issue OI-2026-02-14-010
- Issue ID: OI-2026-02-14-010
- Title: Escape-stop can end capture with status 15 and no output file (screencapture terminated too aggressively)
- Status: Mitigated
- Severity: High
- First Seen: 2026-02-14
- Scope:
  - Affects `New Task` recording stop when using `Escape` (and Stop button if it shares the same stop path).
  - Causes the app to show `Failed to stop capture: Capture ended but no recording file was created (status 15)`.
- Repro Steps:
  1. Start a new recording from `New Task`.
  2. Press `Escape` to stop.
- Observed:
  - Recording stops but no `.mov` is created.
  - Error message shows termination `status 15` (SIGTERM).
- Expected:
  - `Escape` stop finalizes the recording and produces a `.mov` reliably.
- Current Mitigation:
  - Adjusted stop logic to favor graceful stop:
    - send a byte + newline to `screencapture` stdin and close stdin,
    - send SIGINT and wait before escalating,
    - only SIGTERM/SIGKILL if SIGINT does not stop the process in time.
  - Increased output-file finalization wait to reduce false “no file created” errors under load.
- Next Action:
  - User-side runtime validation:
    - `New Task` -> record -> press `Escape` -> confirm a `.mov` is created and the recording-finished sheet appears.
    - repeat with a very short recording (< 1s) and confirm it still produces output.
- Owner: Codex + user validation in local runtime

## Issue OI-2026-02-13-009
- Issue ID: OI-2026-02-13-009
- Title: New Task recording does not reliably hide/restore app UI on non-main display
- Status: Mitigated
- Severity: Medium
- First Seen: 2026-02-13
- Scope:
  - Affects the `New Task` recording experience (the app UI should get out of the way during capture and return afterward).
  - Most noticeable on multi-display setups when the app window is on a non-main display at capture start.
- Repro Steps:
  1. Connect 2+ displays.
  2. Move the ClickCherry app window onto the non-main display.
  3. In `New Task`, start recording (any selected display).
  4. Press `Escape` to stop recording.
- Observed:
  - The app UI did not consistently hide when recording started.
  - After stopping via `Escape`, the app did not always pop back up like the Stop button flow.
- Expected:
  - Starting capture hides the app UI windows across all displays (overlays remain visible).
  - Stopping via `Escape` behaves like Stop: capture stops and the app returns focused (and for `New Task` it should navigate to the new task detail view).
- Current Mitigation:
  - Window hide behavior now targets all normal app UI windows (by window level), not just titled windows.
  - Capture launch is started off the main thread so overlay + hide commands render immediately at recording start (reduces cases where the window remains visible during the first moments of capture).
  - Capture stop restores any windows hidden for capture and re-activates the app.
  - `Escape` stop on the `New Task` route now navigates to the newly created task detail view (same as the Stop button behavior).
- Next Action:
  - User-side runtime validation:
    - start recording from `New Task` while the app window is on the non-main display and confirm the UI hides.
    - press `Escape` to stop and confirm the app reappears focused and navigates to the task detail view.
- Owner: Codex + user validation in local runtime

## Issue OI-2026-02-13-008
- Issue ID: OI-2026-02-13-008
- Title: Recording overlays (border + Escape HUD) do not appear on non-main display
- Status: Mitigated
- Severity: Medium
- First Seen: 2026-02-13
- Scope:
  - Affects New Task screen recording feedback overlays (red border + `Press Escape to stop` HUD).
  - Multi-display setups where the non-main display has a negative global origin (e.g., monitor positioned left/below the main display).
- Repro Steps:
  1. Connect 2+ displays.
  2. In `New Task`, select `Display 2` (non-main).
  3. Start recording.
- Observed:
  - No visible red border overlay and no recording HUD on the selected display.
- Expected:
  - Red border overlay and recording HUD appear on the selected display.
- Current Mitigation:
  - Overlay windows are now created without passing a `screen:` argument to `NSWindow`/`NSPanel` initializers so their frames are interpreted in global screen coordinates.
  - Display indexing for overlays and display thumbnails now uses AppKit screen ordering (`NSScreen`, main first) to align with `screencapture -D` numbering.
  - Build/tests pass; runtime confirmation pending.
- Next Action:
  - User-side runtime validation on a multi-display setup:
    - select `Display 2` and start recording; confirm border + HUD appear on that display.
    - confirm `Display 1` behavior remains unchanged.
- Owner: Codex + user validation in local runtime

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
- Status: Mitigated
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
  - Previously: selecting an explicit mic could cause `screencapture` finalize failures such as `Capture audio device <id> not found`, resulting in failed stop and/or missing output file.
- Expected:
  - Selected explicit microphone should be used directly when available.
  - No fallback warning when the selected device is valid.
- Current Mitigation:
  - Implementation now mitigates by temporarily switching the system default input device for the duration of the recording session, while recording still uses `screencapture -g`.
  - This avoids relying on `screencapture -G<id>`, which was unreliable across devices.
- Next Action:
  - User-side runtime validation:
    - Choose a non-default mic in `New Task`, start recording, then stop recording.
    - Confirm a `.mov` is saved and no `Capture audio device ... not found` error appears.
- Owner: Codex + user validation in local Xcode runtime

# Closed Issues

## Issue OI-2026-02-17-011
- Issue ID: OI-2026-02-17-011
- Title: CI unit tests intermittently fail in Gemini and staged-recording extraction flows
- Status: Closed
- Severity: High
- First Seen: 2026-02-17
- Scope:
  - Affects `TaskAgentMacOSAppTests` in CI for:
    - `GeminiVideoLLMClientTests.analyzeVideoUploadsPollsAndGeneratesExtractionOutput()`
    - `MainShellStateStoreTests.extractFromFinishedRecordingCreatesTaskOnlyAfterExtractionReturns()`
- Repro Steps:
  1. Run CI-equivalent unit tests with `-parallel-testing-enabled NO -only-testing:TaskAgentMacOSAppTests`.
  2. Observe intermittent failure modes from assertion context and continuation timing.
- Observed:
  - Gemini test could record assertion issues from URLProtocol callback context (`unknown` issue context in Swift Testing).
  - Staged recording extraction test could race when `finish(with:)` was called before `BlockingStoreLLMClient` continuation was set.
- Expected:
  - Deterministic unit tests that assert request payloads and staged extraction completion without callback-context assertion traps or dropped completions.
- Current Mitigation:
  - Gemini test now validates captured requests in test context after execution and decodes request JSON to verify `file_uri`, avoiding callback-context assertions.
  - `BlockingStoreLLMClient` now buffers pending `finish`/`fail` outcomes if called before continuation registration, eliminating timing race drops.
  - `MainShellStateStoreTests.extractFromFinishedRecordingCreatesTaskOnlyAfterExtractionReturns` now waits with time-based polling (`Task.sleep`) and explicit timeout instead of `Task.yield` spin loops, preventing scheduler-dependent CI flakiness.
- Next Action:
  - Monitor next GitHub CI runs for stability on the same test cases.
- Owner: Codex
- Resolution Date: 2026-02-17
- Resolution Summary: Applied deterministic test fixes and reran CI-equivalent unit test command locally (`TaskAgentMacOSAppTests`), which passed with 69/69 tests.

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
