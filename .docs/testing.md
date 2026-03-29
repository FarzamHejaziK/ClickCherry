---
description: Testing guidance for TaskAgentMacOSApp, including local commands, release-artifact validation, and permission-specific caveats.
---

# Testing Guide

## Source of truth

- Treat local Xcode or local terminal runs as the authoritative build/test result for source changes.
- Treat the GitHub DMG as the authoritative runtime artifact for release-permission validation.
- For permission regressions, do not stop at local Xcode validation. Compare:
  - Apple Development local build
  - GitHub release DMG / Developer ID hardened-runtime artifact

## Why local and public builds can differ

- Local Xcode runs are signed as `Apple Development`.
- Public DMGs are re-signed as `Developer ID Application` with hardened runtime.
- A local build can pass while the public DMG fails if signing or entitlements differ.
- This is exactly how the March 2026 microphone regression reproduced: local builds showed the native prompt, while the public DMG failed until the hardened-runtime signature included `com.apple.security.device.audio-input`.

## Recommended local test commands

Release build:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/clickcherry-release-local \
  build
```

Unit tests:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/clickcherry-tests-local \
  -only-testing:TaskAgentMacOSAppTests \
  test
```

Optional: force a specific Xcode when multiple versions are installed.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...
```

## Operational notes

- Use a dedicated `-derivedDataPath` to avoid permission or lock conflicts.
- Avoid running multiple `xcodebuild` commands concurrently against the same DerivedData path.
- If you hit stale lock issues, remove the chosen DerivedData directory and rerun.
- Unit tests run inside an XCTest host app process. To avoid macOS Keychain popups during test runs, `KeychainAPIKeyStore` automatically uses in-memory storage when `XCTestConfigurationFilePath` is present.
- Runtime behavior is unchanged outside XCTest: provider keys are still read/written in macOS Keychain.

## MainShell refactor smoke test

Use this focused pass after structural refactors to `MainShellStateStore` or its extension files.

1. Run the targeted store suite:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -only-testing:TaskAgentMacOSAppTests/MainShellStateStoreTests \
  test
```

2. Run a broader build:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  build
```

3. Perform this interactive smoke checklist in the app:
   - Create a task, open another task, and switch back to confirm selection and heartbeat reloads.
   - Open Settings, save a provider key, then clear it and confirm missing-key flows still route correctly.
   - Pin a task, verify it moves to the pinned area, then delete the selected pinned task and confirm the app returns to the new-task route.
   - Edit and save heartbeat content, then reopen the task to confirm persistence.
   - If clarification questions are present, answer one and verify it remains resolved after reload.
   - Trigger run preflight failures, then run a valid task and cancel it with `Esc`.
   - Start and stop capture, then verify the finished-recording review flow appears.
   - Import a supported recording and verify extraction to both a new task and an existing task.

## OpenAI runner refactor smoke test

Use this focused pass after structural refactors to `OpenAIAutomationEngine.swift` or files under `TaskAgentMacOSApp/TaskAgentMacOSApp/Services/OpenAIAutomation/`.

Status:
- Executed successfully on 2026-03-26. Automated coverage passed, app launch smoke passed, and the user reported the live provider-backed smoke pass looked good after following the checklist below.

1. Run the targeted OpenAI runner suite after each extraction slice:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests \
  test
```

2. After the final split, run the broader unit-test target:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -only-testing:TaskAgentMacOSAppTests \
  test
```

3. Run a broader build:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  build
```

4. Perform this interactive smoke checklist in the app:
   - Run one known-safe OpenAI-backed task and confirm the run completes successfully.
   - Run a task that exercises `desktop_action` interactions and verify screenshots and actions still align with the selected display.
   - Run a task that exercises `terminal_exec` and verify stdout/stderr/exit-code behavior is unchanged.
   - Start a run and cancel with `Esc`; confirm the overlay hides and the run ends cleanly.
   - Open diagnostics/run history and confirm trace/log ordering and user-facing error text remain unchanged.

## Execution prompt replay and visual-grounding diagnosis

Use this when execution behavior looks suspicious and you need to validate exactly what the model received.

1. Find the latest run folder under:
   - `/Users/ferzamh/Library/Application Support/TaskAgentMacOS/workspace-<task-id>/runs/`

2. Inspect persisted artifacts:
   - `agent-run-...json` (run trace/events)
   - `agent-run-...-screenshots/` (exact images sent to the model)
   - `agent-run-...-llm-exchanges/` (exact outbound request and inbound response JSON)

3. Validate prompt/runtime selection from run logs:
   - confirm prompt name/version/model lines are present
   - confirm the selected prompt matches `Prompts/execution_agent_openai/config.yaml`

4. Recreate turn-1 behavior outside the app:
   - replay `001-request.json` against the API to test prompt changes against identical input.
   - compare replay response to in-app `001-response.json`.

5. Evaluate with this ordering:
   - screenshot evidence correctness first (what is visibly true),
   - then tool action quality (best next action),
   - then completion validity (was success proven).

6. Manual verification checklist for each diagnostic run:
   - open `001-initial_prompt_image.png` and confirm cursor marker matches cursor location.
   - if a crop is requested, confirm crop image actually contains intended region (for Dock tasks, Dock must be visible).
   - compare final claimed target to visible tooltip/visual evidence in the last screenshot.
   - treat any `SUCCESS` without visible evidence as non-verified.

## Vision-first grounding smoke test

Status:
- Automated verification completed successfully on 2026-03-27.
- Interactive desktop validation is still pending in local runtime.

1. Run the focused grounding suites:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerTests \
  test
```

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -only-testing:TaskAgentMacOSAppTests/DesktopScreenshotTransformServiceTests \
  -only-testing:TaskAgentMacOSAppTests/OpenAIComputerUseRunnerVisionTests \
  test
```

2. Run the broader unit-test target:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  -only-testing:TaskAgentMacOSAppTests \
  test
```

3. Run a clean app build:

```bash
xcodebuild -project /Users/ferzamh/code-git-local/ClickCherry/TaskAgentMacOSApp/TaskAgentMacOSApp.xcodeproj \
  -scheme TaskAgentMacOSApp \
  -destination "platform=macOS" \
  build
```

4. Perform this interactive grounding checklist in the app:
   - Run a task that requires a small precise click and confirm the model uses screenshot -> crop -> click sequencing rather than blind full-screen clicks.
   - Exercise a crop-inside-crop flow on a tiny target and confirm the final click lands correctly.
   - Use a light-background screen and a dark-background screen to confirm the grid overlay remains readable.
   - Run on a non-primary display and confirm crop coordinates still land on the selected display.
   - After a click/type/open action, confirm the next model turn sees a fresh full-display screenshot instead of staying trapped in the prior crop.
   - Attempt a response that would chain screenshot + click in one turn and confirm the later visual step is deferred until the next screenshot.

## Public DMG permission verification

Use this when the bug might depend on release signing, notarization, or hardened runtime.

1. Download the GitHub DMG for the tag under test.
2. Remove all other `ClickCherry` copies and eject all mounted ClickCherry DMGs.
3. Drag `ClickCherry.app` into `/Applications`.
4. Reset permission state before each clean pass:

```bash
tccutil reset ScreenCapture
tccutil reset Microphone com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp
tccutil reset Accessibility com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp
tccutil reset ListenEvent com.farzamh.TaskAgentMacOS.TaskAgentMacOSApp
killall tccd || true
```

5. Launch only `/Applications/ClickCherry.app`.
6. Validate permission flows in this order:
   - Microphone: expect native macOS dialog on first request.
   - Screen Recording: expect System Settings list entry for the installed app.
   - Accessibility / Input Monitoring: expect Settings-first flow.

## Permission-specific caveats

- Microphone:
  - The native macOS dialog is the critical first-registration path.
  - There is no manual `+` add flow in System Settings.
- Screen Recording:
  - The Settings list can preserve stale renamed local test app entries.
  - If Screen Recording shows a backup/test app name instead of `ClickCherry`, treat that as test-environment contamination and redo the clean reset before evaluating product behavior.
- Accessibility / Input Monitoring:
  - These remain Settings-first validations and are more sensitive to duplicate app copies than to signing-entitlement drift.
